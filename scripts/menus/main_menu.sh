#!/usr/bin/env bash
# ==========================================================
# DebMenux - Menu-driven toolkit for Debian homelab/NAS
# ==========================================================
# File: scripts/menus/main_menu.sh
# Description: Main interactive TUI menu using dialog.
# License: MIT
# ==========================================================

set -euo pipefail

# Paths
DEBMENUX_BASE_DIR="${DEBMENUX_BASE_DIR:-/usr/local/share/debmenux}"
DEBMENUX_SCRIPTS="${DEBMENUX_SCRIPTS:-${DEBMENUX_BASE_DIR}/scripts}"
DEBMENUX_LIB="${DEBMENUX_LIB:-${DEBMENUX_BASE_DIR}/lib}"
DEBMENUX_VERSION=$(cat "${DEBMENUX_BASE_DIR}/version.txt" 2>/dev/null || echo "dev")

# Source libraries
source "${DEBMENUX_LIB}/utils.sh"
source "${DEBMENUX_LIB}/docker.sh"

# Ensure dialog is available
if ! command_exists dialog; then
    msg_error "dialog is required for the TUI menu."
    msg_warn "Install with: apt-get install dialog"
    exit 1
fi

# ==============================================================================
# MAIN MENU
# ==============================================================================

show_main_menu() {
    local TEMP_FILE
    TEMP_FILE=$(mktemp)

    while true; do
        dialog --clear \
            --backtitle "DebMenux v${DEBMENUX_VERSION} — Debian Docker Homelab" \
            --title " Main Menu " \
            --menu "\nSelect an option:" 20 65 10 \
            1 "$(t "Install a Service")" \
            2 "$(t "Manage Services") (start/stop/logs)" \
            3 "$(t "Update Services")" \
            4 "$(t "Network Management")" \
            5 "$(t "Storage & Disks")" \
            6 "$(t "Backup & Restore")" \
            7 "$(t "Post-Install Optimization")" \
            8 "$(t "System Info & Utilities")" \
            9 "$(t "Settings")" \
            0 "$(t "Exit")" 2>"$TEMP_FILE"

        local exit_status=$?

        # User pressed Cancel or ESC
        if [[ $exit_status -ne 0 ]]; then
            clear
            msg_ok "$(t "Thank you for using DebMenux. Goodbye!")"
            rm -f "$TEMP_FILE"
            exit 0
        fi

        local option
        option=$(<"$TEMP_FILE")

        case "$option" in
            1) exec bash "${DEBMENUX_SCRIPTS}/menus/services_menu.sh" ;;
            2) show_manage_menu ;;
            3) show_update_menu ;;
            4) show_placeholder "Network Management" ;;
            5) show_placeholder "Storage & Disks" ;;
            6) show_placeholder "Backup & Restore" ;;
            7) show_placeholder "Post-Install Optimization" ;;
            8) show_system_info ;;
            9) show_settings_menu ;;
            0)
                clear
                msg_ok "$(t "Thank you for using DebMenux. Goodbye!")"
                rm -f "$TEMP_FILE"
                exit 0
                ;;
        esac
    done
}

# ==============================================================================
# MANAGE SERVICES SUBMENU
# ==============================================================================

show_manage_menu() {
    local services=()
    local i=1

    # Discover installed services
    while IFS= read -r svc; do
        [[ -z "$svc" ]] && continue
        local status
        status=$(svc_status "$svc")
        services+=("$i" "${svc} [${status}]")
        ((i++))
    done < <(list_services)

    if [[ ${#services[@]} -eq 0 ]]; then
        dialog --backtitle "DebMenux" --title " Manage Services " \
            --msgbox "\nNo services installed in ${DOCKER_DIR}.\n\nInstall one from the service catalog first." 10 50
        return
    fi

    local TEMP_FILE
    TEMP_FILE=$(mktemp)

    dialog --clear \
        --backtitle "DebMenux" \
        --title " Manage Services " \
        --menu "\nSelect a service:" 20 60 10 \
        "${services[@]}" 2>"$TEMP_FILE"

    local exit_status=$?
    [[ $exit_status -ne 0 ]] && { rm -f "$TEMP_FILE"; return; }

    local choice
    choice=$(<"$TEMP_FILE")
    rm -f "$TEMP_FILE"

    # Get service name from choice index
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
        --title " ${svc_name} " \
        --menu "\nAction:" 16 50 7 \
        1 "Start" \
        2 "Stop" \
        3 "Restart" \
        4 "View Logs (last 50)" \
        5 "Update (pull + recreate)" \
        6 "Status" \
        0 "Back" 2>"$TEMP_FILE"

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
        4) svc_logs "$svc_name" 50; echo -e "\n${TAB}Press ENTER to continue..."; read -r ;;
        5) svc_update "$svc_name" ;;
        6) echo -e "\n${TAB}${BOLD}${svc_name}:${CL} $(svc_status "$svc_name")"; echo -e "\n${TAB}Press ENTER to continue..."; read -r ;;
        0) return ;;
    esac

    sleep 1
}

# ==============================================================================
# UPDATE SERVICES
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
        dialog --backtitle "DebMenux" --title " Update Services " \
            --msgbox "\nNo services installed." 8 40
        return
    fi

    local TEMP_FILE
    TEMP_FILE=$(mktemp)

    dialog --clear \
        --backtitle "DebMenux" \
        --title " Update Services " \
        --checklist "\nSelect services to update:" 20 55 10 \
        "${services[@]}" 2>"$TEMP_FILE"

    local exit_status=$?
    [[ $exit_status -ne 0 ]] && { rm -f "$TEMP_FILE"; return; }

    local selected
    selected=$(<"$TEMP_FILE")
    rm -f "$TEMP_FILE"

    clear
    msg_title "Updating selected services"

    for svc_name in $selected; do
        # Remove quotes from dialog output
        svc_name="${svc_name//\"/}"
        svc_update "$svc_name"
    done

    echo -e "\n${TAB}Press ENTER to continue..."
    read -r
}

# ==============================================================================
# SYSTEM INFO
# ==============================================================================

show_system_info() {
    local info=""
    info+="Hostname:   $(hostname)\n"
    info+="IP:         $(get_server_ip)\n"
    info+="OS:         $(lsb_release -ds 2>/dev/null || cat /etc/os-release | grep PRETTY_NAME | cut -d= -f2 | tr -d '\"')\n"
    info+="Kernel:     $(uname -r)\n"
    info+="Uptime:     $(uptime -p)\n"
    info+="\n"
    info+="CPU:        $(grep -c ^processor /proc/cpuinfo) cores\n"
    info+="RAM:        $(free -h | awk '/Mem:/{print $3 "/" $2}')\n"
    info+="Disk /:     $(df -h / | awk 'NR==2{print $3 "/" $2 " (" $5 " used)"}')\n"
    info+="\n"

    if command_exists docker; then
        info+="Docker:     $(docker --version | grep -oP '\d+\.\d+\.\d+')\n"
        info+="Containers: $(docker ps -q | wc -l) running / $(docker ps -aq | wc -l) total\n"
        info+="Images:     $(docker images -q | wc -l)\n"
    else
        info+="Docker:     NOT INSTALLED\n"
    fi

    info+="\nDebMenux:   v${DEBMENUX_VERSION}\n"

    dialog --backtitle "DebMenux" \
        --title " System Information " \
        --msgbox "$info" 22 60
}

# ==============================================================================
# SETTINGS
# ==============================================================================

show_settings_menu() {
    local TEMP_FILE
    TEMP_FILE=$(mktemp)

    dialog --clear \
        --backtitle "DebMenux" \
        --title " Settings " \
        --menu "\nConfigure DebMenux:" 14 50 4 \
        1 "Change Language" \
        2 "Change Docker Directory" \
        3 "Check for Updates" \
        0 "Back" 2>"$TEMP_FILE"

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
        --title " Language " \
        --menu "\nSelect language:" 10 40 3 \
        "es" "Español" \
        "en" "English" 2>"$TEMP_FILE"

    local exit_status=$?
    [[ $exit_status -ne 0 ]] && { rm -f "$TEMP_FILE"; return; }

    local new_lang
    new_lang=$(<"$TEMP_FILE")
    rm -f "$TEMP_FILE"

    # Update config
    local tmp_config
    tmp_config=$(mktemp)
    jq --arg lang "$new_lang" '.language = $lang' "$DEBMENUX_CONFIG" > "$tmp_config" 2>/dev/null
    mv "$tmp_config" "$DEBMENUX_CONFIG"

    export DEBMENUX_LANG="$new_lang"
    load_language

    dialog --backtitle "DebMenux" --title " Language " \
        --msgbox "\nLanguage changed to: ${new_lang}\n\nRestart the menu for full effect." 10 45
}

change_docker_dir() {
    local TEMP_FILE
    TEMP_FILE=$(mktemp)

    dialog --clear \
        --backtitle "DebMenux" \
        --title " Docker Directory " \
        --inputbox "\nPath where Docker services are stored:\n(current: ${DOCKER_DIR})" 12 55 "${DOCKER_DIR}" 2>"$TEMP_FILE"

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

        dialog --backtitle "DebMenux" --title " Docker Directory " \
            --msgbox "\nDocker directory set to: ${new_dir}" 8 50
    fi
}

check_updates() {
    clear
    msg_info "Checking for updates"
    # TODO: Compare local version.txt with remote
    sleep 2
    msg_ok "You are running the latest version (v${DEBMENUX_VERSION})"
    sleep 2
}

# ==============================================================================
# PLACEHOLDER
# ==============================================================================

show_placeholder() {
    local title="$1"
    dialog --backtitle "DebMenux" \
        --title " ${title} " \
        --msgbox "\n🚧 This module is under development.\n\nComing soon in a future release." 10 50
}

# ==============================================================================
# ENTRY POINT
# ==============================================================================

show_main_menu
