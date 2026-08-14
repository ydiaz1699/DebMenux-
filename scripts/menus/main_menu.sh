#!/usr/bin/env bash
# ==========================================================
# DebMenux — Toolkit interactivo para homelab Debian + Docker
# ==========================================================
# Archivo: scripts/menus/main_menu.sh
# Descripción: Menú TUI principal usando dialog.
# Licencia: MIT
# ==========================================================

set -euo pipefail

DEBMENUX_BASE_DIR="${DEBMENUX_BASE_DIR:-/debmenux}"
DEBMENUX_SCRIPTS="${DEBMENUX_SCRIPTS:-${DEBMENUX_BASE_DIR}/scripts}"
DEBMENUX_LIB="${DEBMENUX_LIB:-${DEBMENUX_BASE_DIR}/lib}"
DEBMENUX_VERSION=$(cat "${DEBMENUX_BASE_DIR}/version.txt" 2>/dev/null || echo "dev")

source "${DEBMENUX_LIB}/utils.sh"
source "${DEBMENUX_LIB}/docker.sh"
source "${DEBMENUX_LIB}/integration.sh"

if ! command_exists dialog; then
    msg_error "Se requiere 'dialog' para el menú TUI."
    msg_warn "Instala con: apt-get install dialog"
    exit 1
fi

# ==============================================================================
# MENÚ PRINCIPAL
# ==============================================================================

show_main_menu() {
    local TEMP_FILE
    TEMP_FILE=$(mktemp)

    while true; do
        dialog --clear \
            --backtitle "🐧 DebMenux v${DEBMENUX_VERSION} — Homelab Debian + Docker" \
            --title " 🏠 Menú Principal " \
            --menu "\nSelecciona una opción:" 20 65 10 \
            1 "📦 Instalar un Servicio" \
            2 "🔧 Gestionar Servicios (iniciar/detener/logs)" \
            3 "🆙 Actualizar Servicios" \
            4 "🌐 Gestión de Red" \
            5 "💾 Almacenamiento y Discos" \
            6 "🗄️  Backup y Restauración" \
            7 "⚙️  Optimización Post-Instalación" \
            8 "📊 Info del Sistema y Utilidades" \
            9 "🔩 Configuración" \
            0 "🚪 Salir" 2>"$TEMP_FILE"

        local exit_status=$?

        if [[ $exit_status -ne 0 ]]; then
            clear
            msg_ok "¡Gracias por usar DebMenux! Hasta luego 👋"
            rm -f "$TEMP_FILE"
            exit 0
        fi

        local option
        option=$(<"$TEMP_FILE")

        case "$option" in
            1) exec bash "${DEBMENUX_SCRIPTS}/menus/services_menu.sh" ;;
            2) show_manage_menu ;;
            3) show_update_menu ;;
            4) show_placeholder "🌐 Gestión de Red" ;;
            5) show_placeholder "💾 Almacenamiento y Discos" ;;
            6) show_placeholder "🗄️ Backup y Restauración" ;;
            7) show_post_install_menu ;;
            8) show_system_info ;;
            9) show_settings_menu ;;
            0)
                clear
                msg_ok "¡Gracias por usar DebMenux! Hasta luego 👋"
                rm -f "$TEMP_FILE"
                exit 0
                ;;
        esac
    done
}

# ==============================================================================
# SUBMENÚ: GESTIONAR SERVICIOS
# ==============================================================================

show_manage_menu() {
    local services=()
    local i=1

    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue
        local status
        status=$(svc_status "$svc")
        services+=("$i" "${svc} [${status}]")
        ((i++))
    done < <(list_services)

    if [[ ${#services[@]} -eq 0 ]]; then
        dialog --backtitle "DebMenux" --title " 🔧 Gestionar Servicios " \
            --msgbox "\n❌ No hay servicios instalados en ${DOCKER_DIR}.\n\nInstala uno desde el catálogo primero." 10 50
        return
    fi

    local TEMP_FILE
    TEMP_FILE=$(mktemp)

    dialog --clear \
        --backtitle "DebMenux" \
        --title " 🔧 Gestionar Servicios " \
        --menu "\nSelecciona un servicio:" 20 60 10 \
        "${services[@]}" 2>"$TEMP_FILE"

    local exit_status=$?
    [[ $exit_status -ne 0 ]] && { rm -f "$TEMP_FILE"; return; }

    local choice
    choice=$(<"$TEMP_FILE")
    rm -f "$TEMP_FILE"

    local idx=$(( (choice - 1) * 2 + 1 ))
    local svc_entry="${services[$idx]}"
    local svc_name="${svc_entry%% \[*}"

    show_service_actions "$svc_name"
}

show_service_actions() {
    local svc_name="$1"
    local TEMP_FILE
    TEMP_FILE=$(mktemp)

    dialog --clear \
        --backtitle "DebMenux" \
        --title " 🔧 ${svc_name} " \
        --menu "\nAcción:" 16 50 7 \
        1 "▶️  Iniciar" \
        2 "⏹️  Detener" \
        3 "🔄 Reiniciar" \
        4 "📋 Ver Logs (últimos 50)" \
        5 "🆙 Actualizar (pull + recrear)" \
        6 "📊 Estado" \
        0 "↩️  Volver" 2>"$TEMP_FILE"

    local exit_status=$?
    [[ $exit_status -ne 0 ]] && { rm -f "$TEMP_FILE"; return; }

    local action
    action=$(<"$TEMP_FILE")
    rm -f "$TEMP_FILE"

    clear
    case "$action" in
        1) svc_up "$svc_name" ;;
        2) svc_down "$svc_name" ;;
        3) svc_restart "$svc_name" ;;
        4) svc_logs "$svc_name" 50; echo -e "\n${TAB}Presiona ENTER para continuar..."; read -r ;;
        5) svc_update "$svc_name" ;;
        6) echo -e "\n${TAB}${BOLD}${svc_name}:${CL} $(svc_status "$svc_name")"; echo -e "\n${TAB}Presiona ENTER para continuar..."; read -r ;;
        0) return ;;
    esac

    sleep 1
}

# ==============================================================================
# SUBMENÚ: ACTUALIZAR SERVICIOS
# ==============================================================================

show_update_menu() {
    local services=()
    local i=1

    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue
        services+=("$svc" "" "on")
        ((i++))
    done < <(list_services)

    if [[ ${#services[@]} -eq 0 ]]; then
        dialog --backtitle "DebMenux" --title " 🆙 Actualizar Servicios " \
            --msgbox "\n❌ No hay servicios instalados." 8 40
        return
    fi

    local TEMP_FILE
    TEMP_FILE=$(mktemp)

    dialog --clear \
        --backtitle "DebMenux" \
        --title " 🆙 Actualizar Servicios " \
        --checklist "\nSelecciona servicios a actualizar:" 20 55 10 \
        "${services[@]}" 2>"$TEMP_FILE"

    local exit_status=$?
    [[ $exit_status -ne 0 ]] && { rm -f "$TEMP_FILE"; return; }

    local selected
    selected=$(<"$TEMP_FILE")
    rm -f "$TEMP_FILE"

    clear
    msg_title "🆙 Actualizando servicios seleccionados"

    for svc_name in $selected; do
        svc_name="${svc_name//\"/}"
        svc_update "$svc_name"
    done

    echo -e "\n${TAB}Presiona ENTER para continuar..."
    read -r
}

# ==============================================================================
# INFO DEL SISTEMA
# ==============================================================================

show_system_info() {
    local info=""
    info+="🖥️  Hostname:    $(hostname)\n"
    info+="🌐 IP:          $(get_server_ip)\n"
    info+="🐧 SO:          $(lsb_release -ds 2>/dev/null || grep PRETTY_NAME /etc/os-release | cut -d= -f2 | tr -d '\"')\n"
    info+="⚙️  Kernel:      $(uname -r)\n"
    info+="⏱️  Uptime:      $(uptime -p)\n"
    info+="\n"
    info+="🔲 CPU:         $(grep -c ^processor /proc/cpuinfo) núcleos\n"
    info+="💾 RAM:         $(free -h | awk '/Mem:/{print $3 "/" $2}')\n"
    info+="💿 Disco /:     $(df -h / | awk 'NR==2{print $3 "/" $2 " (" $5 " usado)"}')\n"
    info+="\n"

    if command_exists docker; then
        info+="🐳 Docker:      $(docker --version | grep -oP '\d+\.\d+\.\d+')\n"
        info+="📦 Contenedores: $(docker ps -q | wc -l) corriendo / $(docker ps -aq | wc -l) total\n"
        info+="🖼️  Imágenes:    $(docker images -q | wc -l)\n"
    else
        info+="🐳 Docker:      NO INSTALADO\n"
    fi

    info+="\n🐧 DebMenux:    v${DEBMENUX_VERSION}\n"

    dialog --backtitle "DebMenux" \
        --title " 📊 Información del Sistema " \
        --msgbox "$info" 22 60
}

# ==============================================================================
# CONFIGURACIÓN
# ==============================================================================

show_settings_menu() {
    local TEMP_FILE
    TEMP_FILE=$(mktemp)

    dialog --clear \
        --backtitle "DebMenux" \
        --title " 🔩 Configuración " \
        --menu "\nConfigurar DebMenux:" 14 50 4 \
        1 "🌐 Cambiar Idioma" \
        2 "📁 Cambiar Directorio Docker" \
        3 "🔄 Buscar Actualizaciones" \
        0 "↩️  Volver" 2>"$TEMP_FILE"

    local exit_status=$?
    [[ $exit_status -ne 0 ]] && { rm -f "$TEMP_FILE"; return; }

    local option
    option=$(<"$TEMP_FILE")
    rm -f "$TEMP_FILE"

    case "$option" in
        1) change_language ;;
        2) change_docker_dir ;;
        3) check_updates ;;
        0) return ;;
    esac
}

change_language() {
    local TEMP_FILE
    TEMP_FILE=$(mktemp)

    dialog --clear \
        --backtitle "DebMenux" \
        --title " 🌐 Idioma " \
        --menu "\nSelecciona idioma:" 10 40 3 \
        "es" "🇪🇸 Español" \
        "en" "🇬🇧 English" 2>"$TEMP_FILE"

    local exit_status=$?
    [[ $exit_status -ne 0 ]] && { rm -f "$TEMP_FILE"; return; }

    local new_lang
    new_lang=$(<"$TEMP_FILE")
    rm -f "$TEMP_FILE"

    local tmp_config
    tmp_config=$(mktemp)
    jq --arg lang "$new_lang" '.language = $lang' "$DEBMENUX_CONFIG" > "$tmp_config" 2>/dev/null
    mv "$tmp_config" "$DEBMENUX_CONFIG"

    export DEBMENUX_LANG="$new_lang"
    load_language

    dialog --backtitle "DebMenux" --title " 🌐 Idioma " \
        --msgbox "\n✅ Idioma cambiado a: ${new_lang}\n\nReinicia el menú para efecto completo." 10 45
}

change_docker_dir() {
    local TEMP_FILE
    TEMP_FILE=$(mktemp)

    dialog --clear \
        --backtitle "DebMenux" \
        --title " 📁 Directorio Docker " \
        --inputbox "\nRuta donde se almacenan los servicios Docker:\n(actual: ${DOCKER_DIR})" 12 55 "${DOCKER_DIR}" 2>"$TEMP_FILE"

    local exit_status=$?
    [[ $exit_status -ne 0 ]] && { rm -f "$TEMP_FILE"; return; }

    local new_dir
    new_dir=$(<"$TEMP_FILE")
    rm -f "$TEMP_FILE"

    if [[ -n "$new_dir" ]]; then
        local tmp_config
        tmp_config=$(mktemp)
        jq --arg dir "$new_dir" '.docker_dir = $dir' "$DEBMENUX_CONFIG" > "$tmp_config" 2>/dev/null
        mv "$tmp_config" "$DEBMENUX_CONFIG"
        export DOCKER_DIR="$new_dir"

        dialog --backtitle "DebMenux" --title " 📁 Directorio Docker " \
            --msgbox "\n✅ Directorio Docker: ${new_dir}" 8 50
    fi
}

check_updates() {
    clear
    msg_info "Buscando actualizaciones"
    sleep 2
    msg_ok "Estás ejecutando la última versión (v${DEBMENUX_VERSION}) 🎉"
    sleep 2
}

# ==============================================================================
# SUBMENÚ: POST-INSTALACIÓN
# ==============================================================================

show_post_install_menu() {
    local TEMP_FILE
    TEMP_FILE=$(mktemp)

    dialog --clear \
        --backtitle "🐧 DebMenux — Post-Instalación" \
        --title " ⚙️ Optimización Post-Instalación " \
        --menu "\nConfigura y optimiza tu servidor:" 16 60 6 \
        1 "🔌 Automontaje USB (instalar/configurar)" \
        2 "📊 Estado del Automontaje USB" \
        3 "⏏️  Desinstalar Automontaje USB" \
        4 "🐳 Instalar Docker" \
        5 "🐧 Optimizar Debian (swap, sysctl, zram)" \
        0 "↩️  Volver al Menú Principal" 2>"$TEMP_FILE"

    local exit_status=$?
    [[ $exit_status -ne 0 ]] && { rm -f "$TEMP_FILE"; return; }

    local option
    option=$(<"$TEMP_FILE")
    rm -f "$TEMP_FILE"

    case "$option" in
        1)
            clear
            msg_title "🔌 Instalando Automontaje USB"
            source "${DEBMENUX_SCRIPTS}/post-install/usb-automount.sh"
            install_service
            echo -e "\n${TAB}Presiona ENTER para continuar..."
            read -r
            show_post_install_menu
            ;;
        2)
            clear
            source "${DEBMENUX_SCRIPTS}/post-install/usb-automount.sh"
            show_status
            echo -e "\n${TAB}Presiona ENTER para continuar..."
            read -r
            show_post_install_menu
            ;;
        3)
            clear
            source "${DEBMENUX_SCRIPTS}/post-install/usb-automount.sh"
            uninstall_service
            echo -e "\n${TAB}Presiona ENTER para continuar..."
            read -r
            show_post_install_menu
            ;;
        4) show_placeholder "🐳 Instalar Docker" ; show_post_install_menu ;;
        5) show_placeholder "🐧 Optimizar Debian" ; show_post_install_menu ;;
        0) return ;;
    esac
}

# ==============================================================================
# PLACEHOLDER
# ==============================================================================

show_placeholder() {
    local title="$1"
    dialog --backtitle "DebMenux" \
        --title " ${title} " \
        --msgbox "\n🚧 Este módulo está en desarrollo.\n\nPróximamente en una futura versión." 10 50
}

# ==============================================================================
# PUNTO DE ENTRADA
# ==============================================================================

show_main_menu
