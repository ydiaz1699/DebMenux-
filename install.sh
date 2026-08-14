#!/usr/bin/env bash
# ==========================================================
# DebMenux - Menu-driven toolkit for Debian homelab/NAS
# ==========================================================
# File: install.sh
# Description: One-liner installer. Downloads and installs
#              DebMenux on any Debian-based system with Docker.
#
# Usage:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/ydiaz1699/DebMenux-/main/install.sh)"
#
# License: MIT
# ==========================================================

set -euo pipefail

# Configuration
REPO_URL="https://github.com/ydiaz1699/DebMenux-.git"
BASE_DIR="/usr/local/share/debmenux"
INSTALL_DIR="/usr/local/bin"
CONFIG_FILE="${BASE_DIR}/config.json"
MENU_CMD="debmenu"
VERSION="0.1.0"

# Colors (inline for the installer — lib/utils.sh not yet available)
GN="\033[1;92m"
RD="\033[01;31m"
YW="\033[33m"
YWB="\033[1;33m"
BL="\033[36m"
BOLD="\033[1m"
CL="\033[m"
TAB="    "
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"

SPINNER_PID=""

spinner() {
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local spin_i=0
    printf "\e[?25l"
    while true; do
        printf "\r ${YW}%s${CL}" "${frames[spin_i]}"
        spin_i=$(( (spin_i + 1) % ${#frames[@]} ))
        sleep 0.1
    done
}

stop_spinner() {
    if [[ -n "$SPINNER_PID" ]] && ps -p "$SPINNER_PID" > /dev/null 2>&1; then
        kill "$SPINNER_PID" > /dev/null 2>&1
        wait "$SPINNER_PID" 2>/dev/null
    fi
    printf "\r\033[K\e[?25h"
    SPINNER_PID=""
}

msg_info() {
    echo -ne "${TAB}${YW}- ${1}${CL}"
    spinner &
    SPINNER_PID=$!
}

msg_ok() {
    stop_spinner
    echo -e "${TAB}${CM} ${GN}${1}${CL}"
}

msg_error() {
    stop_spinner
    echo -e "${TAB}${CROSS} ${RD}${1}${CL}"
}

msg_warn() {
    stop_spinner
    echo -e "${TAB}${YWB}⚠ ${1}${CL}"
}

cleanup() {
    stop_spinner
    rm -rf /tmp/debmenux-install-$$ 2>/dev/null || true
}
trap cleanup EXIT

# ==============================================================================
# LOGO
# ==============================================================================

show_logo() {
    clear
    echo -e ""
    echo -e "${TAB}${BOLD}${BL}╔══════════════════════════════════════╗${CL}"
    echo -e "${TAB}${BOLD}${BL}║                                      ║${CL}"
    echo -e "${TAB}${BOLD}${BL}║${CL}    ${BOLD}🐧 DebMenux${CL}  ${GN}v${VERSION}${CL}             ${BOLD}${BL}║${CL}"
    echo -e "${TAB}${BOLD}${BL}║${CL}                                      ${BOLD}${BL}║${CL}"
    echo -e "${TAB}${BOLD}${BL}║${CL}    ${BOLD}Menu-driven toolkit for${CL}            ${BOLD}${BL}║${CL}"
    echo -e "${TAB}${BOLD}${BL}║${CL}    ${BOLD}Debian Docker homelab${CL}              ${BOLD}${BL}║${CL}"
    echo -e "${TAB}${BOLD}${BL}║${CL}                                      ${BOLD}${BL}║${CL}"
    echo -e "${TAB}${BOLD}${BL}╚══════════════════════════════════════╝${CL}"
    echo -e ""
}

# ==============================================================================
# PRE-FLIGHT CHECKS
# ==============================================================================

preflight_checks() {
    # Must be root
    if [[ "$(id -u)" -ne 0 ]]; then
        msg_error "This script must be run as root."
        echo -e "${TAB}Run: ${YWB}sudo bash install.sh${CL}"
        exit 1
    fi

    # Must be Debian-based
    if [[ ! -f /etc/debian_version ]]; then
        msg_error "This toolkit requires a Debian-based system."
        exit 1
    fi

    # Check internet connectivity
    if ! ping -c 1 -W 3 github.com &>/dev/null; then
        msg_error "No internet connectivity. Cannot reach github.com."
        exit 1
    fi

    msg_ok "Pre-flight checks passed"
}

# ==============================================================================
# LANGUAGE SELECTION
# ==============================================================================

select_language() {
    # Check if dialog is available for language selection
    if command -v dialog &>/dev/null; then
        local lang
        lang=$(dialog --clear --backtitle "DebMenux Installer" \
            --title "Select Language / Seleccionar Idioma" \
            --menu "\nChoose your language:" 12 50 4 \
            "es" "Español" \
            "en" "English" \
            3>&1 1>&2 2>&3) || lang="es"
        clear
        DEBMENUX_LANG="$lang"
    else
        # Fallback: simple prompt
        echo -e "${TAB}${BL}?${CL} Select language / Seleccionar idioma:"
        echo -e "${TAB}  1) Español (default)"
        echo -e "${TAB}  2) English"
        read -rp "$(echo -e "${TAB}  → ")" choice
        case "$choice" in
            2) DEBMENUX_LANG="en" ;;
            *) DEBMENUX_LANG="es" ;;
        esac
    fi

    msg_ok "Language: ${DEBMENUX_LANG}"
}

# ==============================================================================
# INSTALL DEPENDENCIES
# ==============================================================================

install_dependencies() {
    msg_info "Updating package lists"
    apt-get update -qq > /dev/null 2>&1
    msg_ok "Package lists updated"

    local deps=("dialog" "curl" "jq" "git")

    for pkg in "${deps[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            msg_info "Installing ${pkg}"
            apt-get install -y "$pkg" > /dev/null 2>&1
            if [[ $? -eq 0 ]]; then
                msg_ok "${pkg} installed"
            else
                msg_error "Failed to install ${pkg}"
                exit 1
            fi
        fi
    done

    msg_ok "All dependencies satisfied"
}

# ==============================================================================
# INSTALL DOCKER (if not present)
# ==============================================================================

install_docker() {
    if command -v docker &>/dev/null; then
        local docker_ver
        docker_ver=$(docker --version | grep -oP '\d+\.\d+\.\d+')
        msg_ok "Docker already installed (v${docker_ver})"
        return 0
    fi

    if ! confirm_install_docker; then
        msg_warn "Docker not installed. Service scripts will not work without Docker."
        return 0
    fi

    msg_info "Installing Docker via official script"
    curl -fsSL https://get.docker.com | sh > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        systemctl enable --now docker > /dev/null 2>&1
        msg_ok "Docker installed and started"
    else
        msg_error "Docker installation failed"
        msg_warn "Install manually: https://docs.docker.com/engine/install/debian/"
        return 1
    fi
}

confirm_install_docker() {
    echo -e ""
    echo -e "${TAB}${YWB}Docker is not installed.${CL}"
    echo -e "${TAB}DebMenux requires Docker for service management."
    echo -e ""
    read -rp "$(echo -e "${TAB}${BL}?${CL} Install Docker now? [Y/n]: ")" answer
    answer="${answer:-y}"
    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

# ==============================================================================
# CLONE & INSTALL FILES
# ==============================================================================

install_files() {
    local temp_dir="/tmp/debmenux-install-$$"

    msg_info "Cloning DebMenux repository"
    git clone --depth 1 "$REPO_URL" "$temp_dir" > /dev/null 2>&1
    if [[ $? -ne 0 ]]; then
        msg_error "Failed to clone repository"
        exit 1
    fi
    msg_ok "Repository cloned"

    msg_info "Installing DebMenux files"

    # Create base directory
    mkdir -p "$BASE_DIR"
    mkdir -p "${BASE_DIR}/scripts"
    mkdir -p "${BASE_DIR}/lib"
    mkdir -p "${BASE_DIR}/lang"

    # Copy core files
    cp -r "${temp_dir}/lib/"* "${BASE_DIR}/lib/"
    cp -r "${temp_dir}/scripts/"* "${BASE_DIR}/scripts/"
    cp -r "${temp_dir}/lang/"* "${BASE_DIR}/lang/" 2>/dev/null || true
    cp "${temp_dir}/services.json" "${BASE_DIR}/services.json" 2>/dev/null || true

    # Install menu command
    cp "${temp_dir}/menu" "${INSTALL_DIR}/${MENU_CMD}"
    chmod +x "${INSTALL_DIR}/${MENU_CMD}"

    # Make all .sh files executable
    find "${BASE_DIR}" -type f -name '*.sh' -exec chmod +x {} +

    # Store version
    echo "$VERSION" > "${BASE_DIR}/version.txt"

    msg_ok "DebMenux files installed"

    # Create config if not exists
    if [[ ! -f "$CONFIG_FILE" ]]; then
        # Detect integration config to read DOCKER_DIR
        local detected_docker_dir="/docker"
        local integration_conf=""

        for conf_candidate in \
            "${DEBMENUX_CONF:-}" \
            "/etc/debmenux/debmenux.conf" \
            "${HOME}/.config/debmenux/debmenux.conf"; do
            if [[ -n "$conf_candidate" && -f "$conf_candidate" ]]; then
                integration_conf="$conf_candidate"
                break
            fi
        done

        if [[ -n "$integration_conf" ]]; then
            local parsed_docker_dir
            parsed_docker_dir=$(grep -E "^DOCKER_DIR=" "$integration_conf" 2>/dev/null | head -1 | cut -d= -f2 | xargs)
            parsed_docker_dir="${parsed_docker_dir/#\~/$HOME}"
            if [[ -n "$parsed_docker_dir" ]]; then
                detected_docker_dir="$parsed_docker_dir"
            fi
            msg_ok "Integration config detected: ${integration_conf}"
        fi

        cat > "$CONFIG_FILE" <<EOF
{
    "language": "${DEBMENUX_LANG:-es}",
    "docker_dir": "${detected_docker_dir}",
    "version": "${VERSION}",
    "installed_at": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
    "integration_conf": "${integration_conf}"
}
EOF
        msg_ok "Configuration created (docker_dir: ${detected_docker_dir})"
    fi

    # Cleanup
    rm -rf "$temp_dir"
}

# ==============================================================================
# POST-INSTALL
# ==============================================================================

show_post_install() {
    echo -e ""
    echo -e "${TAB}${BOLD}${GN}━━━ Installation complete! ━━━${CL}"
    echo -e ""
    echo -e "${TAB}${BOLD}To launch DebMenux:${CL}"
    echo -e "${TAB}  ${YWB}${MENU_CMD}${CL}"
    echo -e ""
    echo -e "${TAB}${BOLD}To install a service directly:${CL}"
    echo -e "${TAB}  ${YWB}${MENU_CMD} install <service>${CL}"
    echo -e ""
    echo -e "${TAB}${BOLD}Examples:${CL}"
    echo -e "${TAB}  ${MENU_CMD} install adguard"
    echo -e "${TAB}  ${MENU_CMD} install emqx"
    echo -e "${TAB}  ${MENU_CMD} list"
    echo -e ""

    local server_ip
    server_ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || hostname -I | awk '{print $1}')
    echo -e "${TAB}${BOLD}Server IP:${CL} ${BL}${server_ip:-localhost}${CL}"
    echo -e ""
}

# ==============================================================================
# MAIN
# ==============================================================================

main() {
    show_logo
    preflight_checks
    select_language
    install_dependencies
    install_docker
    install_files
    show_post_install
}

main "$@"
