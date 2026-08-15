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
TEMPLATE_DIR="${DEBMENUX_BASE_DIR:-/debmenux}/templates/usb-automount"

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
# HELPERS DE VALIDACIÓN
# ==============================================================================

# Validar que un valor es una ruta absoluta segura
_validate_path() {
    local path="$1"
    # Debe empezar con / y solo contener: letras, números, /, _, ., -
    # NO permite: espacios, acentos, |, ;, $, etc. (por seguridad en sed/mount)
    if [[ ! "$path" =~ ^/[a-zA-Z0-9/_.-]+$ ]]; then
        return 1
    fi
    return 0
}

# Mensaje de error para ruta inválida (explica restricciones)
_path_error_msg() {
    local path="$1"
    echo -e "\nRuta inválida: ${path}\n\nDebe ser ruta absoluta sin espacios ni caracteres\nespeciales. Permitidos: letras, números, / _ . -\n\nEjemplos válidos:\n  /media\n  /NAS/USB\n  /mnt/usb-drives"
}

# Validar que un valor es numérico
_validate_numeric() {
    local value="$1"
    [[ "$value" =~ ^[0-9]+$ ]]
}

# Ejecutar paso con verificación de error
_run_step() {
    local description="$1"
    shift
    msg_info "$description"
    if "$@"; then
        msg_ok "$description ✅"
        return 0
    else
        msg_error "Falló: $description"
        return 1
    fi
}

# ==============================================================================
# CONFIGURACIÓN INTERACTIVA (compartida por install y edit)
# ==============================================================================

# Lee la configuración actual de CONFIG_DEST si existe (para edit_config)
_load_current_config() {
    local mount_base_default="/media"
    local uid_default="1000"
    local gid_default="1000"
    local whitelist_default="false"
    local blacklist_default="false"
    local notifications_default="false"
    local loglevel_default="INFO"

    if [[ -f "$CONFIG_DEST" ]]; then
        mount_base_default=$(grep "^MOUNT_BASE=" "$CONFIG_DEST" 2>/dev/null | cut -d'"' -f2)
        uid_default=$(grep "^DEFAULT_UID=" "$CONFIG_DEST" 2>/dev/null | cut -d= -f2)
        gid_default=$(grep "^DEFAULT_GID=" "$CONFIG_DEST" 2>/dev/null | cut -d= -f2)
        whitelist_default=$(grep "^WHITELIST_ENABLED=" "$CONFIG_DEST" 2>/dev/null | cut -d'"' -f2)
        blacklist_default=$(grep "^BLACKLIST_ENABLED=" "$CONFIG_DEST" 2>/dev/null | cut -d'"' -f2)
        notifications_default=$(grep "^ENABLE_NOTIFICATIONS=" "$CONFIG_DEST" 2>/dev/null | cut -d'"' -f2)
        loglevel_default=$(grep "^LOG_LEVEL=" "$CONFIG_DEST" 2>/dev/null | cut -d'"' -f2)
    fi

    # Exportar como variables para el dialog
    _CFG_MOUNT_BASE="${mount_base_default:-/media}"
    _CFG_UID="${uid_default:-1000}"
    _CFG_GID="${gid_default:-1000}"
    _CFG_WHITELIST="${whitelist_default:-false}"
    _CFG_BLACKLIST="${blacklist_default:-false}"
    _CFG_NOTIFICATIONS="${notifications_default:-false}"
    _CFG_LOGLEVEL="${loglevel_default:-INFO}"
}

# Mostrar dialogs de configuración. Usa _CFG_* como defaults.
# Escribe resultados en _CFG_* variables.
_interactive_config() {
    if command -v dialog &>/dev/null; then
        local TEMP_FILE
        TEMP_FILE=$(mktemp)

        # Ruta de montaje
        dialog --clear \
            --backtitle "🐧 DebMenux — Automontaje USB" \
            --title " 📁 Ruta de Montaje " \
            --inputbox "\n¿Dónde montar los dispositivos USB?\n\nCada USB se montará en: <ruta>/usb-<dispositivo>\n" 12 55 "$_CFG_MOUNT_BASE" 2>"$TEMP_FILE"
        [[ $? -eq 0 ]] && _CFG_MOUNT_BASE=$(<"$TEMP_FILE")

        # Validar ruta
        if ! _validate_path "$_CFG_MOUNT_BASE"; then
            dialog --backtitle "DebMenux" --title " ❌ Error " \
                --msgbox "$(_path_error_msg "$_CFG_MOUNT_BASE")" 14 55
            rm -f "$TEMP_FILE"
            return 1
        fi

        # UID
        dialog --clear \
            --backtitle "🐧 DebMenux — Automontaje USB" \
            --title " 👤 Permisos " \
            --inputbox "\nUID del usuario para permisos de montaje\n(FAT32, exFAT, NTFS):\n\nUsa 'id <usuario>' para verificar." 12 55 "$_CFG_UID" 2>"$TEMP_FILE"
        [[ $? -eq 0 ]] && _CFG_UID=$(<"$TEMP_FILE")

        # Validar UID numérico
        if ! _validate_numeric "$_CFG_UID"; then
            dialog --backtitle "DebMenux" --title " ❌ Error " \
                --msgbox "\nUID inválido: $_CFG_UID\n\nDebe ser un número (ej. 0, 1000)." 9 50
            rm -f "$TEMP_FILE"
            return 1
        fi

        # GID
        dialog --clear \
            --backtitle "🐧 DebMenux — Automontaje USB" \
            --title " 👤 Permisos " \
            --inputbox "\nGID del grupo para permisos de montaje:" 10 55 "$_CFG_GID" 2>"$TEMP_FILE"
        [[ $? -eq 0 ]] && _CFG_GID=$(<"$TEMP_FILE")

        # Validar GID numérico
        if ! _validate_numeric "$_CFG_GID"; then
            dialog --backtitle "DebMenux" --title " ❌ Error " \
                --msgbox "\nGID inválido: $_CFG_GID\n\nDebe ser un número (ej. 0, 1000)." 9 50
            rm -f "$TEMP_FILE"
            return 1
        fi

        # Opciones de seguridad (pre-seleccionar las activas)
        local wl_flag="off" bl_flag="off" nt_flag="off" db_flag="off"
        [[ "$_CFG_WHITELIST" == "true" ]] && wl_flag="on"
        [[ "$_CFG_BLACKLIST" == "true" ]] && bl_flag="on"
        [[ "$_CFG_NOTIFICATIONS" == "true" ]] && nt_flag="on"
        [[ "$_CFG_LOGLEVEL" == "DEBUG" ]] && db_flag="on"

        local security_choices
        security_choices=$(dialog --clear \
            --backtitle "🐧 DebMenux — Automontaje USB" \
            --title " 🛡️ Seguridad " \
            --checklist "\nOpciones de seguridad:" 14 55 4 \
            "whitelist" "Solo montar USBs autorizados" "$wl_flag" \
            "blacklist" "Bloquear USBs específicos" "$bl_flag" \
            "notifications" "Notificaciones de escritorio" "$nt_flag" \
            "debug" "Logging en modo DEBUG" "$db_flag" \
            3>&1 1>&2 2>&3)

        # Resetear y re-parsear
        _CFG_WHITELIST="false"
        _CFG_BLACKLIST="false"
        _CFG_NOTIFICATIONS="false"
        _CFG_LOGLEVEL="INFO"
        [[ "$security_choices" == *"whitelist"* ]] && _CFG_WHITELIST="true"
        [[ "$security_choices" == *"blacklist"* ]] && _CFG_BLACKLIST="true"
        [[ "$security_choices" == *"notifications"* ]] && _CFG_NOTIFICATIONS="true"
        [[ "$security_choices" == *"debug"* ]] && _CFG_LOGLEVEL="DEBUG"

        rm -f "$TEMP_FILE"
        clear
    else
        # Fallback sin dialog: mostrar valores actuales
        echo -e ""
        echo -e "${TAB}${BOLD}📋 Configuración actual:${CL}"
        echo -e "${TAB}  Ruta de montaje: ${BL}${_CFG_MOUNT_BASE}${CL}"
        echo -e "${TAB}  UID/GID:         ${BL}${_CFG_UID}:${_CFG_GID}${CL}"
        echo -e "${TAB}  Whitelist:       ${_CFG_WHITELIST}"
        echo -e "${TAB}  Blacklist:       ${_CFG_BLACKLIST}"
        echo -e "${TAB}  Notificaciones:  ${_CFG_NOTIFICATIONS}"
        echo -e "${TAB}  Log level:       ${_CFG_LOGLEVEL}"
        echo -e ""
        echo -e "${TAB}${DIM}(Sin dialog — usando valores actuales/por defecto)${CL}"
        echo -e ""
    fi

    return 0
}

# Generar /etc/usb-automount.conf desde las variables _CFG_*
_write_config() {
    # Backup de config existente (si es reinstalación)
    if [[ -f "$CONFIG_DEST" ]]; then
        cp "$CONFIG_DEST" "${CONFIG_DEST}.bak" 2>/dev/null || true
    fi

    sed -e "s|^MOUNT_BASE=.*|MOUNT_BASE=\"${_CFG_MOUNT_BASE}\"|" \
        -e "s|^DEFAULT_UID=.*|DEFAULT_UID=${_CFG_UID}|" \
        -e "s|^DEFAULT_GID=.*|DEFAULT_GID=${_CFG_GID}|" \
        -e "s|^WHITELIST_ENABLED=.*|WHITELIST_ENABLED=\"${_CFG_WHITELIST}\"|" \
        -e "s|^BLACKLIST_ENABLED=.*|BLACKLIST_ENABLED=\"${_CFG_BLACKLIST}\"|" \
        -e "s|^ENABLE_NOTIFICATIONS=.*|ENABLE_NOTIFICATIONS=\"${_CFG_NOTIFICATIONS}\"|" \
        -e "s|^LOG_LEVEL=.*|LOG_LEVEL=\"${_CFG_LOGLEVEL}\"|" \
        "$TEMPLATE_DIR/usb-automount.conf" > "$CONFIG_DEST"
    chmod 644 "$CONFIG_DEST"
}

# ==============================================================================
# INSTALACIÓN
# ==============================================================================

install_service() {
    # ── Verificar si ya está instalado ────────────────────────
    if [[ -f "$SCRIPT_DEST" && -f "$UDEV_DEST" ]]; then
        msg_warn "⚠️  USB Automount ya está instalado."
        if ! confirm "¿Reinstalar/actualizar?"; then
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
    _load_current_config
    if ! _interactive_config; then
        msg_error "Configuración cancelada o inválida"
        return 1
    fi

    # ── Paso 3: Copiar script principal ───────────────────────
    msg_info "Instalando script de automontaje"
    if ! cp "$TEMPLATE_DIR/usb-automount.sh" "$SCRIPT_DEST"; then
        msg_error "No se pudo copiar script a $SCRIPT_DEST (¿disco lleno?)"
        return 1
    fi
    chmod +x "$SCRIPT_DEST"
    chown root:root "$SCRIPT_DEST"
    msg_ok "Script instalado en $SCRIPT_DEST 📄"

    # ── Paso 4: Generar configuración ─────────────────────────
    msg_info "Generando configuración"
    _write_config
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
    if ! cp "$TEMPLATE_DIR/99-usb-automount.rules" "$UDEV_DEST"; then
        msg_error "No se pudo copiar regla udev"
        return 1
    fi
    chmod 644 "$UDEV_DEST"
    msg_ok "Regla udev instalada 🔌"

    # ── Paso 7: Instalar servicios systemd ────────────────────
    msg_info "Configurando servicios systemd"
    cp "$TEMPLATE_DIR/usb-automount@.service" "$SERVICE_DEST" || { msg_error "Falló copia de service"; return 1; }
    cp "$TEMPLATE_DIR/usb-automount-cleanup.service" "$CLEANUP_SERVICE_DEST" || { msg_error "Falló copia de cleanup service"; return 1; }
    cp "$TEMPLATE_DIR/usb-automount-cleanup.timer" "$CLEANUP_TIMER_DEST" || { msg_error "Falló copia de timer"; return 1; }
    chmod 644 "$SERVICE_DEST" "$CLEANUP_SERVICE_DEST" "$CLEANUP_TIMER_DEST"

    systemctl daemon-reload
    systemctl enable usb-automount-cleanup.timer > /dev/null 2>&1
    systemctl start usb-automount-cleanup.timer > /dev/null 2>&1
    msg_ok "Servicios systemd configurados ⚙️"

    # ── Paso 8: Instalar logrotate ────────────────────────────
    msg_info "Configurando rotación de logs"
    cp "$TEMPLATE_DIR/usb-automount-logrotate" "$LOGROTATE_DEST" || { msg_error "Falló copia de logrotate"; return 1; }
    chmod 644 "$LOGROTATE_DEST"
    msg_ok "Logrotate configurado 📋"

    # ── Paso 9: Crear directorio de montaje ───────────────────
    msg_info "Creando directorio base de montaje"
    mkdir -p "$_CFG_MOUNT_BASE"
    msg_ok "Directorio $_CFG_MOUNT_BASE creado 📁"

    # ── Paso 10: Recargar udev ────────────────────────────────
    msg_info "Recargando reglas udev"
    udevadm control --reload-rules 2>/dev/null || true
    udevadm trigger 2>/dev/null || true
    msg_ok "Reglas udev recargadas 🔄"

    # ── Paso 11: Instalar notify-send si se habilitó ──────────
    if [[ "$_CFG_NOTIFICATIONS" == "true" ]]; then
        if ! command -v notify-send &>/dev/null; then
            msg_info "Instalando libnotify-bin para notificaciones"
            apt-get install -y libnotify-bin > /dev/null 2>&1 && \
                msg_ok "libnotify-bin instalado 📢" || \
                msg_warn "No se pudo instalar libnotify-bin"
        fi
    fi

    # ── Mostrar resumen ───────────────────────────────────────
    _show_summary

    # ── Registrar en catálogo (scope aislado) ─────────────────
    if declare -f register_to_catalog &>/dev/null; then
        (
            APP="USB AutoMount"
            APP_ID="usb-automount"
            IMAGE="system/udev+systemd"
            CATEGORY="post-install"
            NETWORKS=()
            register_to_catalog 2>/dev/null || true
        )
    fi
}

# ==============================================================================
# EDITAR CONFIGURACIÓN (sin reinstalar)
# ==============================================================================

edit_config() {
    msg_title "🔧 Editar Configuración de Automontaje USB"

    if [[ ! -f "$SCRIPT_DEST" ]]; then
        msg_error "USB Automount no está instalado. Instálalo primero."
        return 1
    fi

    if [[ ! -f "$CONFIG_DEST" ]]; then
        msg_error "Archivo de configuración no encontrado: $CONFIG_DEST"
        return 1
    fi

    # Cargar valores actuales como defaults
    _load_current_config

    echo -e "${TAB}${DIM}Valores actuales se mostrarán como defaults en el dialog.${CL}"
    echo -e ""

    # Mostrar dialog con valores pre-cargados
    if ! _interactive_config; then
        msg_error "Edición cancelada o valores inválidos"
        return 1
    fi

    # Guardar nueva configuración (con backup)
    msg_info "Guardando configuración"
    _write_config
    msg_ok "Configuración actualizada ⚙️"

    # Crear directorio si cambió la ruta
    if ! mkdir -p "$_CFG_MOUNT_BASE" 2>/dev/null; then
        msg_warn "No se pudo crear $_CFG_MOUNT_BASE (verificar permisos/disco)"
    fi

    # Recargar udev (por si cambiaron opciones que afectan el comportamiento)
    msg_info "Recargando udev"
    udevadm control --reload-rules 2>/dev/null || true
    msg_ok "Reglas recargadas 🔄"

    echo -e ""
    echo -e "${TAB}${DIM}Backup de config anterior: ${CONFIG_DEST}.bak${CL}"
    _show_summary
}

# ==============================================================================
# RESUMEN
# ==============================================================================

_show_summary() {
    echo -e ""
    msg_success "🔌 Automontaje USB — configuración activa"
    echo -e ""
    echo -e "${TAB}${BOLD}📋 Configuración:${CL}"
    echo -e "${TAB}  Ruta de montaje:   ${BL}${_CFG_MOUNT_BASE}/usb-<dispositivo>${CL}"
    echo -e "${TAB}  UID/GID:           ${BL}${_CFG_UID}:${_CFG_GID}${CL}"
    echo -e "${TAB}  Whitelist:         $(if [[ "$_CFG_WHITELIST" == "true" ]]; then echo "${GN}habilitada${CL}"; else echo "${DIM}deshabilitada${CL}"; fi)"
    echo -e "${TAB}  Blacklist:         $(if [[ "$_CFG_BLACKLIST" == "true" ]]; then echo "${GN}habilitada${CL}"; else echo "${DIM}deshabilitada${CL}"; fi)"
    echo -e "${TAB}  Notificaciones:    $(if [[ "$_CFG_NOTIFICATIONS" == "true" ]]; then echo "${GN}habilitadas${CL}"; else echo "${DIM}deshabilitadas${CL}"; fi)"
    echo -e "${TAB}  Log:               ${BL}/var/log/usb-automount.log${CL} (${_CFG_LOGLEVEL})"
    echo -e ""
    echo -e "${TAB}${BOLD}🧪 Prueba:${CL}"
    echo -e "${TAB}  Conecta un USB y verifica:"
    echo -e "${TAB}  ${YWB}ls ${_CFG_MOUNT_BASE}/usb-*${CL}"
    echo -e "${TAB}  ${YWB}tail -f /var/log/usb-automount.log${CL}"
    echo -e ""
    echo -e "${TAB}${BOLD}📝 Archivos:${CL}"
    echo -e "${TAB}  Script:     ${DIM}${SCRIPT_DEST}${CL}"
    echo -e "${TAB}  Config:     ${DIM}${CONFIG_DEST}${CL}"
    echo -e "${TAB}  Udev:       ${DIM}${UDEV_DEST}${CL}"
    echo -e "${TAB}  Whitelist:  ${DIM}${WHITELIST_DEST}${CL}"
    echo -e "${TAB}  Blacklist:  ${DIM}${BLACKLIST_DEST}${CL}"
    echo -e ""
}

# ==============================================================================
# DESMONTAJE FORZADO / LIMPIEZA MANUAL
# ==============================================================================

force_cleanup() {
    msg_title "🧹 Desmontaje Forzado y Limpieza"

    if [[ ! -f "$SCRIPT_DEST" ]]; then
        msg_error "USB Automount no está instalado."
        return 1
    fi

    # Obtener mount_base de config
    local mount_base="/media"
    if [[ -f "$CONFIG_DEST" ]]; then
        mount_base=$(grep "^MOUNT_BASE=" "$CONFIG_DEST" 2>/dev/null | cut -d'"' -f2)
        mount_base="${mount_base:-/media}"
    fi

    # Listar USBs montados y huérfanos
    local old_nullglob
    old_nullglob=$(shopt -p nullglob 2>/dev/null || true)
    shopt -s nullglob

    local mounted_dirs=()
    local orphan_dirs=()

    for dir in "$mount_base"/usb-*; do
        [[ -d "$dir" ]] || continue
        if mountpoint -q "$dir" 2>/dev/null; then
            mounted_dirs+=("$dir")
        else
            orphan_dirs+=("$dir")
        fi
    done

    eval "$old_nullglob" 2>/dev/null || true

    local total=$(( ${#mounted_dirs[@]} + ${#orphan_dirs[@]} ))

    if [[ $total -eq 0 ]]; then
        msg_ok "No hay puntos de montaje USB activos ni huérfanos 🧹"
        return 0
    fi

    # Mostrar estado
    echo -e "${TAB}${BOLD}📋 Puntos de montaje encontrados:${CL}"
    echo -e ""

    for dir in "${mounted_dirs[@]}"; do
        local dev_name
        dev_name=$(basename "$dir" | sed 's/usb-//')
        local fs_type
        fs_type=$(findmnt -n -o FSTYPE "$dir" 2>/dev/null || echo "?")
        echo -e "${TAB}  🟢 ${BOLD}${dir}${CL} (montado, ${fs_type})"
    done

    for dir in "${orphan_dirs[@]}"; do
        echo -e "${TAB}  🟡 ${BOLD}${dir}${CL} (huérfano — no montado)"
    done

    echo -e ""

    # Confirmar
    if ! confirm "¿Desmontar TODOS y limpiar directorios? (${total} encontrados)"; then
        return 0
    fi

    # Desmontar los que están activos
    local failed=0
    for dir in "${mounted_dirs[@]}"; do
        msg_info "Desmontando ${dir}"
        if umount "$dir" 2>/dev/null; then
            msg_ok "Desmontado: ${dir}"
        elif umount -f "$dir" 2>/dev/null; then
            msg_ok "Desmontado (forzado): ${dir}"
        elif umount -l "$dir" 2>/dev/null; then
            msg_warn "Desmontado (lazy): ${dir} — verificar que no queden procesos"
        else
            msg_error "No se pudo desmontar: ${dir}"
            ((failed++))
            continue
        fi
        # Limpiar directorio
        if [[ -d "$dir" ]] && [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
            rmdir "$dir" 2>/dev/null
        fi
    done

    # Limpiar huérfanos
    for dir in "${orphan_dirs[@]}"; do
        if [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
            rmdir "$dir" 2>/dev/null && \
                msg_ok "Huérfano eliminado: ${dir}" || \
                msg_warn "No se pudo eliminar: ${dir}"
        else
            msg_warn "Huérfano no vacío (no se elimina): ${dir}"
        fi
    done

    echo -e ""
    if [[ $failed -eq 0 ]]; then
        msg_success "🧹 Limpieza completada — todo limpio"
    else
        msg_warn "Limpieza completada con ${failed} error(es)"
        echo -e "${TAB}${DIM}Revisa: lsof +D ${mount_base} (procesos usando los mounts)${CL}"
    fi
    echo -e ""
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
        mount_base=$(grep "^MOUNT_BASE=" "$CONFIG_DEST" 2>/dev/null | cut -d'"' -f2)
        mount_base="${mount_base:-/media}"
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

    # Usar nullglob para evitar iterar sobre el literal si no hay match
    local old_nullglob
    old_nullglob=$(shopt -p nullglob 2>/dev/null || true)
    shopt -s nullglob

    for dir in "$mount_base"/usb-*; do
        if [[ -d "$dir" ]] && mountpoint -q "$dir" 2>/dev/null; then
            local dev_name
            dev_name=$(basename "$dir" | sed 's/usb-//')
            local fs_type
            fs_type=$(findmnt -n -o FSTYPE "$dir" 2>/dev/null || echo "?")
            local size
            size=$(findmnt -n -o SIZE "$dir" 2>/dev/null || echo "?")
            echo -e "${TAB}  🟢 ${BOLD}${dev_name}${CL} → ${dir} (${fs_type}, ${size})"
            mounted=1
        fi
    done

    # Restaurar nullglob
    eval "$old_nullglob" 2>/dev/null || true

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
