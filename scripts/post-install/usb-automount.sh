#!/usr/bin/env bash
# ==========================================================
# DebMenux — Post-Instalación: Automontaje USB
# ==========================================================
# Descripción: Instalador interactivo para configurar el
#              automontaje/desmontaje de dispositivos USB.
#
# Combina lo mejor de:
#   - USB-AutoMount-Linux (funcionalidad base)
#   - Automontaje-MSA (seguridad, modularidad)
#
# Funcionalidades:
#   🔌 Montaje automático al conectar USB
#   ⏏️  Desmontaje automático al desconectar
#   🛡️  Whitelist/Blacklist de dispositivos
#   📋 Logging con niveles y rotación
#   🧹 Limpieza periódica de huérfanos
#   📢 Notificaciones de escritorio (opcional)
#   🔒 Opciones de montaje seguras (noexec, nosuid, nodev)
#
# Licencia: MIT
# ==========================================================

# ==============================================================================
# METADATOS
# ==============================================================================

APP="Automontaje USB"
APP_ID="usb-automount"
CATEGORY="post-install"

# Rutas de templates
TEMPLATE_DIR="${DEBMENUX_BASE_DIR:-/usr/local/share/debmenux}/templates/usb-automount"

# Destinos de instalación
SCRIPT_DEST="/usr/local/bin/usb-automount.sh"
CONFIG_DEST="/etc/usb-automount.conf"
UDEV_DEST="/etc/udev/rules.d/99-usb-automount.rules"
SERVICE_DEST="/etc/systemd/system/usb-automount@.service"
CLEANUP_SERVICE_DEST="/etc/systemd/system/usb-automount-cleanup.service"
CLEANUP_TIMER_DEST="/etc/systemd/system/usb-automount-cleanup.timer"
LOGROTATE_DEST="/etc/logrotate.d/usb-automount"
WHITELIST_DEST="/etc/usb-automount-whitelist.conf"
BLACKLIST_DEST="/etc/usb-automount-blacklist.conf"

# ==============================================================================
# INSTALACIÓN
# ==============================================================================

install_service() {
    # ── Verificar si ya está instalado ────────────────────────
    if [[ -f "$SCRIPT_DEST" && -f "$UDEV_DEST" ]]; then
        msg_warn "⚠️  USB Automount ya está instalado."
        if ! confirm "¿Reinstalar/actualizar?"; then
            msg_info "Instalación cancelada"
            stop_spinner
            return 0
        fi
    fi

    # ── Verificar templates ───────────────────────────────────
    if [[ ! -d "$TEMPLATE_DIR" ]]; then
        msg_error "Directorio de templates no encontrado: $TEMPLATE_DIR"
        return 1
    fi

    # ── Paso 1: Instalar dependencias ─────────────────────────
    msg_info "Instalando dependencias de filesystem"
    local deps=("ntfs-3g" "exfatprogs" "btrfs-progs")
    local installed=()

    for pkg in "${deps[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            if apt-get install -y "$pkg" > /dev/null 2>&1; then
                installed+=("$pkg")
            fi
        fi
    done

    if [[ ${#installed[@]} -gt 0 ]]; then
        msg_ok "Dependencias instaladas: ${installed[*]} 📦"
    else
        msg_ok "Dependencias ya satisfechas 📦"
    fi

    # ── Paso 2: Configuración interactiva ─────────────────────
    local mount_base="/media"
    local default_uid default_gid
    default_uid=$(id -u "${SUDO_USER:-root}" 2>/dev/null || echo 1000)
    default_gid=$(id -g "${SUDO_USER:-root}" 2>/dev/null || echo 1000)
    local enable_whitelist="false"
    local enable_blacklist="false"
    local enable_notifications="false"
    local log_level="INFO"

    # Dialog para configuración
    if command -v dialog &>/dev/null; then
        local TEMP_FILE
        TEMP_FILE=$(mktemp)

        # Ruta de montaje
        dialog --clear \
            --backtitle "🐧 DebMenux — Automontaje USB" \
            --title " 📁 Ruta de Montaje " \
            --inputbox "\n¿Dónde montar los dispositivos USB?\n\nCada USB se montará en: <ruta>/usb-<dispositivo>\n" 12 55 "$mount_base" 2>"$TEMP_FILE"
        [[ $? -eq 0 ]] && mount_base=$(<"$TEMP_FILE")

        # UID/GID
        dialog --clear \
            --backtitle "🐧 DebMenux — Automontaje USB" \
            --title " 👤 Permisos " \
            --inputbox "\nUID del usuario para permisos de montaje\n(FAT32, exFAT, NTFS):\n\nUsa 'id <usuario>' para verificar." 12 55 "$default_uid" 2>"$TEMP_FILE"
        [[ $? -eq 0 ]] && default_uid=$(<"$TEMP_FILE")

        dialog --clear \
            --backtitle "🐧 DebMenux — Automontaje USB" \
            --title " 👤 Permisos " \
            --inputbox "\nGID del grupo para permisos de montaje:" 10 55 "$default_gid" 2>"$TEMP_FILE"
        [[ $? -eq 0 ]] && default_gid=$(<"$TEMP_FILE")

        # Opciones de seguridad
        local security_choices
        security_choices=$(dialog --clear \
            --backtitle "🐧 DebMenux — Automontaje USB" \
            --title " 🛡️ Seguridad " \
            --checklist "\nOpciones de seguridad:" 14 55 4 \
            "whitelist" "Solo montar USBs autorizados" off \
            "blacklist" "Bloquear USBs específicos" off \
            "notifications" "Notificaciones de escritorio" off \
            "debug" "Logging en modo DEBUG" off \
            3>&1 1>&2 2>&3)

        [[ "$security_choices" == *"whitelist"* ]] && enable_whitelist="true"
        [[ "$security_choices" == *"blacklist"* ]] && enable_blacklist="true"
        [[ "$security_choices" == *"notifications"* ]] && enable_notifications="true"
        [[ "$security_choices" == *"debug"* ]] && log_level="DEBUG"

        rm -f "$TEMP_FILE"
        clear
    else
        # Fallback sin dialog: usar valores por defecto
        msg_info "Usando configuración por defecto (sin dialog)"
        stop_spinner
        echo -e "${TAB}  Ruta de montaje: ${BL}${mount_base}${CL}"
        echo -e "${TAB}  UID/GID: ${BL}${default_uid}:${default_gid}${CL}"
        echo -e ""
    fi

    # ── Paso 3: Copiar script principal ───────────────────────
    msg_info "Instalando script de automontaje"
    cp "$TEMPLATE_DIR/usb-automount.sh" "$SCRIPT_DEST"
    chmod +x "$SCRIPT_DEST"
    chown root:root "$SCRIPT_DEST"
    msg_ok "Script instalado en $SCRIPT_DEST 📄"

    # ── Paso 4: Generar configuración ─────────────────────────
    msg_info "Generando configuración"
    sed -e "s|^MOUNT_BASE=.*|MOUNT_BASE=\"${mount_base}\"|" \
        -e "s|^DEFAULT_UID=.*|DEFAULT_UID=${default_uid}|" \
        -e "s|^DEFAULT_GID=.*|DEFAULT_GID=${default_gid}|" \
        -e "s|^WHITELIST_ENABLED=.*|WHITELIST_ENABLED=\"${enable_whitelist}\"|" \
        -e "s|^BLACKLIST_ENABLED=.*|BLACKLIST_ENABLED=\"${enable_blacklist}\"|" \
        -e "s|^ENABLE_NOTIFICATIONS=.*|ENABLE_NOTIFICATIONS=\"${enable_notifications}\"|" \
        -e "s|^LOG_LEVEL=.*|LOG_LEVEL=\"${log_level}\"|" \
        "$TEMPLATE_DIR/usb-automount.conf" > "$CONFIG_DEST"
    chmod 644 "$CONFIG_DEST"
    msg_ok "Configuración generada en $CONFIG_DEST ⚙️"

    # ── Paso 5: Copiar whitelist/blacklist ────────────────────
    if [[ ! -f "$WHITELIST_DEST" ]]; then
        cp "$TEMPLATE_DIR/whitelist.conf.example" "$WHITELIST_DEST"
    fi
    if [[ ! -f "$BLACKLIST_DEST" ]]; then
        cp "$TEMPLATE_DIR/blacklist.conf.example" "$BLACKLIST_DEST"
    fi

    # ── Paso 6: Instalar regla udev ──────────────────────────
    msg_info "Instalando regla udev"
    cp "$TEMPLATE_DIR/99-usb-automount.rules" "$UDEV_DEST"
    chmod 644 "$UDEV_DEST"
    msg_ok "Regla udev instalada 🔌"

    # ── Paso 7: Instalar servicios systemd ────────────────────
    msg_info "Configurando servicios systemd"
    cp "$TEMPLATE_DIR/usb-automount@.service" "$SERVICE_DEST"
    cp "$TEMPLATE_DIR/usb-automount-cleanup.service" "$CLEANUP_SERVICE_DEST"
    cp "$TEMPLATE_DIR/usb-automount-cleanup.timer" "$CLEANUP_TIMER_DEST"
    chmod 644 "$SERVICE_DEST" "$CLEANUP_SERVICE_DEST" "$CLEANUP_TIMER_DEST"

    systemctl daemon-reload
    systemctl enable usb-automount-cleanup.timer > /dev/null 2>&1
    systemctl start usb-automount-cleanup.timer > /dev/null 2>&1
    msg_ok "Servicios systemd configurados ⚙️"

    # ── Paso 8: Instalar logrotate ────────────────────────────
    msg_info "Configurando rotación de logs"
    cp "$TEMPLATE_DIR/usb-automount-logrotate" "$LOGROTATE_DEST"
    chmod 644 "$LOGROTATE_DEST"
    msg_ok "Logrotate configurado 📋"

    # ── Paso 9: Crear directorio de montaje ───────────────────
    msg_info "Creando directorio base de montaje"
    mkdir -p "$mount_base"
    msg_ok "Directorio $mount_base creado 📁"

    # ── Paso 10: Recargar udev ────────────────────────────────
    msg_info "Recargando reglas udev"
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger 2>/dev/null || true
    msg_ok "Reglas udev recargadas 🔄"

    # ── Paso 11: Instalar notify-send si se habilitó ──────────
    if [[ "$enable_notifications" == "true" ]]; then
        if ! command -v notify-send &>/dev/null; then
            msg_info "Instalando libnotify-bin para notificaciones"
            apt-get install -y libnotify-bin > /dev/null 2>&1 && \
                msg_ok "libnotify-bin instalado 📢" || \
                msg_warn "No se pudo instalar libnotify-bin"
        fi
    fi

    # ── Mostrar resumen ───────────────────────────────────────
    echo -e ""
    msg_success "🔌 Automontaje USB instalado exitosamente!"
    echo -e ""
    echo -e "${TAB}${BOLD}📋 Configuración:${CL}"
    echo -e "${TAB}  Ruta de montaje:   ${BL}${mount_base}/usb-<dispositivo>${CL}"
    echo -e "${TAB}  UID/GID:           ${BL}${default_uid}:${default_gid}${CL}"
    echo -e "${TAB}  Whitelist:         $(if [[ "$enable_whitelist" == "true" ]]; then echo "${GN}habilitada${CL}"; else echo "${DIM}deshabilitada${CL}"; fi)"
    echo -e "${TAB}  Blacklist:         $(if [[ "$enable_blacklist" == "true" ]]; then echo "${GN}habilitada${CL}"; else echo "${DIM}deshabilitada${CL}"; fi)"
    echo -e "${TAB}  Notificaciones:    $(if [[ "$enable_notifications" == "true" ]]; then echo "${GN}habilitadas${CL}"; else echo "${DIM}deshabilitadas${CL}"; fi)"
    echo -e "${TAB}  Log:               ${BL}/var/log/usb-automount.log${CL} (${log_level})"
    echo -e ""
    echo -e "${TAB}${BOLD}🧪 Prueba:${CL}"
    echo -e "${TAB}  Conecta un USB y verifica:"
    echo -e "${TAB}  ${YWB}ls ${mount_base}/usb-*${CL}"
    echo -e "${TAB}  ${YWB}tail -f /var/log/usb-automount.log${CL}"
    echo -e ""
    echo -e "${TAB}${BOLD}📝 Archivos:${CL}"
    echo -e "${TAB}  Script:     ${DIM}${SCRIPT_DEST}${CL}"
    echo -e "${TAB}  Config:     ${DIM}${CONFIG_DEST}${CL}"
    echo -e "${TAB}  Udev:       ${DIM}${UDEV_DEST}${CL}"
    echo -e "${TAB}  Whitelist:  ${DIM}${WHITELIST_DEST}${CL}"
    echo -e "${TAB}  Blacklist:  ${DIM}${BLACKLIST_DEST}${CL}"
    echo -e ""

    # Registrar en catálogo externo si integración habilitada
    if declare -f register_to_catalog &>/dev/null; then
        # Fake vars para el registro (no es Docker pero el hook es útil)
        APP="USB AutoMount"
        APP_ID="usb-automount"
        IMAGE="system/udev+systemd"
        CATEGORY="post-install"
        NETWORKS=()
        register_to_catalog 2>/dev/null || true
    fi
}

# ==============================================================================
# DESINSTALACIÓN
# ==============================================================================

uninstall_service() {
    msg_title "⏏️ Desinstalando Automontaje USB"

    if [[ ! -f "$SCRIPT_DEST" ]]; then
        msg_error "USB Automount no está instalado."
        return 1
    fi

    if ! confirm "¿Desinstalar Automontaje USB? (los datos en USB no se afectan)"; then
        return 0
    fi

    msg_info "Deteniendo servicios"
    systemctl stop usb-automount-cleanup.timer 2>/dev/null || true
    systemctl disable usb-automount-cleanup.timer 2>/dev/null || true
    msg_ok "Servicios detenidos"

    msg_info "Eliminando archivos"
    rm -f "$SCRIPT_DEST"
    rm -f "$UDEV_DEST"
    rm -f "$SERVICE_DEST"
    rm -f "$CLEANUP_SERVICE_DEST"
    rm -f "$CLEANUP_TIMER_DEST"
    rm -f "$LOGROTATE_DEST"
    # No eliminar config ni whitelist/blacklist (datos del usuario)
    msg_ok "Archivos eliminados"

    msg_info "Recargando servicios"
    systemctl daemon-reload
    udevadm control --reload-rules 2>/dev/null || true
    msg_ok "Sistema actualizado"

    echo -e ""
    msg_success "⏏️ Automontaje USB desinstalado"
    echo -e "${TAB}${DIM}Nota: Se conservaron ${CONFIG_DEST} y las listas blanca/negra.${CL}"
    echo -e "${TAB}${DIM}Eliminar manualmente si no se necesitan.${CL}"
    echo -e ""
}

# ==============================================================================
# ESTADO
# ==============================================================================

show_status() {
    echo -e ""
    msg_title "📊 Estado del Automontaje USB"

    if [[ ! -f "$SCRIPT_DEST" ]]; then
        msg_error "USB Automount no está instalado."
        echo -e "${TAB}Instala con: ${YWB}debmenu${CL} → Post-Instalación → Automontaje USB"
        echo -e ""
        return 1
    fi

    # Obtener config
    local mount_base="/media"
    if [[ -f "$CONFIG_DEST" ]]; then
        mount_base=$(grep "^MOUNT_BASE=" "$CONFIG_DEST" | cut -d'"' -f2)
    fi

    echo -e "${TAB}${BOLD}🔌 Instalación:${CL} ${GN}activa${CL}"
    echo -e "${TAB}${BOLD}📁 Ruta:${CL}        $mount_base"
    echo -e ""

    # Timer activo?
    if systemctl is-active --quiet usb-automount-cleanup.timer 2>/dev/null; then
        echo -e "${TAB}${BOLD}⏱️  Cleanup timer:${CL} ${GN}activo${CL}"
    else
        echo -e "${TAB}${BOLD}⏱️  Cleanup timer:${CL} ${RD}inactivo${CL}"
    fi

    # USBs montados actualmente
    echo -e ""
    echo -e "${TAB}${BOLD}📋 USBs montados ahora:${CL}"
    local mounted=0
    for dir in "$mount_base"/usb-*; do
        if [[ -d "$dir" ]] && mountpoint -q "$dir" 2>/dev/null; then
            local dev_name
            dev_name=$(basename "$dir" | sed 's/usb-//')
            local fs_type
            fs_type=$(findmnt -n -o FSTYPE "$dir" 2>/dev/null)
            local size
            size=$(findmnt -n -o SIZE "$dir" 2>/dev/null)
            echo -e "${TAB}  🟢 ${BOLD}${dev_name}${CL} → ${dir} (${fs_type}, ${size})"
            mounted=1
        fi
    done
    if [[ $mounted -eq 0 ]]; then
        echo -e "${TAB}  ${DIM}(ninguno)${CL}"
    fi

    # Últimas líneas del log
    echo -e ""
    echo -e "${TAB}${BOLD}📋 Últimos eventos:${CL}"
    if [[ -f /var/log/usb-automount.log ]]; then
        tail -5 /var/log/usb-automount.log | while IFS= read -r line; do
            echo -e "${TAB}  ${DIM}${line}${CL}"
        done
    else
        echo -e "${TAB}  ${DIM}(sin log)${CL}"
    fi
    echo -e ""
}
