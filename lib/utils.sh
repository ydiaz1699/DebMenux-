#!/usr/bin/env bash
# ==========================================================
# DebMenux - Menu-driven toolkit for Debian homelab/NAS
# ==========================================================
# File: lib/utils.sh
# Description: Core utility functions — colors, spinners,
#              messages, translations, and common helpers.
# License: MIT
# ==========================================================

# Prevent double-sourcing
[[ -n "${__DEBMENUX_UTILS_LOADED:-}" ]] && return 0
__DEBMENUX_UTILS_LOADED=1

# ==============================================================================
# SECTION 1: COLOR & STYLE DEFINITIONS
# ==============================================================================

# Reset
CL="\033[m"
RESET="\033[0m"

# Regular colors
RD="\033[01;31m"
GN="\033[1;92m"
YW="\033[33m"
YWB="\033[1;33m"
BL="\033[36m"
BOLD="\033[1m"
DIM="\033[2m"
WHITE="\033[38;5;15m"
DARK_GRAY="\033[38;5;244m"
ORANGE="\033[38;5;208m"
PURPLE="\033[38;5;99m"

# Symbols
CM="${GN}✓${CL}"
CROSS="${RD}✗${CL}"
ARROW="${BL}➜${CL}"
INFO_ICON="${YW}ℹ${CL}"
WARN_ICON="${ORANGE}⚠${CL}"
TAB="    "
HOLD="-"
BFR="\\r\\033[K"

# ==============================================================================
# SECTION 2: SPINNER
# ==============================================================================

SPINNER_PID=""

spinner() {
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local spin_i=0
    local interval=0.1
    local color="${YW}"

    printf "\e[?25l"  # Hide cursor

    while true; do
        printf "\r ${color}%s${CL}" "${frames[spin_i]}"
        spin_i=$(( (spin_i + 1) % ${#frames[@]} ))
        sleep "$interval"
    done
}

stop_spinner() {
    if [[ -n "$SPINNER_PID" ]] && ps -p "$SPINNER_PID" > /dev/null 2>&1; then
        kill "$SPINNER_PID" > /dev/null 2>&1
        wait "$SPINNER_PID" 2>/dev/null
    fi
    printf "\r\033[K"   # Clear line
    printf "\e[?25h"    # Show cursor
    SPINNER_PID=""
}

# ==============================================================================
# SECTION 3: MESSAGE FUNCTIONS
# ==============================================================================

msg_info() {
    local msg="$1"
    echo -ne "${TAB}${YW}${HOLD} ${msg}${CL}"
    spinner &
    SPINNER_PID=$!
}

msg_ok() {
    stop_spinner
    local msg="$1"
    echo -e "${BFR}${TAB}${CM} ${GN}${msg}${CL}"
}

msg_error() {
    stop_spinner
    local msg="$1"
    echo -e "${BFR}${TAB}${CROSS} ${RD}${msg}${CL}"
}

msg_warn() {
    stop_spinner
    local msg="$1"
    echo -e "${BFR}${TAB}${WARN_ICON} ${YWB}${msg}${CL}"
}

msg_title() {
    local msg="$1"
    echo -e "\n${TAB}${BOLD}━━━ ${msg} ━━━${CL}\n"
}

msg_success() {
    stop_spinner
    local msg="$1"
    echo -e "${BFR}${TAB}${CM} ${BOLD}${GN}${msg}${CL}\n"
}

# Print a separator line
msg_separator() {
    echo -e "${TAB}${DARK_GRAY}────────────────────────────────────────${CL}"
}

# ==============================================================================
# SECTION 4: SYSTEM HELPERS
# ==============================================================================

# Check if running as root
check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        msg_error "This script must be run as root (sudo)."
        exit 1
    fi
}

# Get the primary IP of the server
get_server_ip() {
    local ip
    ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+')
    [[ -z "$ip" ]] && ip=$(hostname -I | awk '{print $1}')
    [[ -z "$ip" ]] && ip="localhost"
    echo "$ip"
}

# Check if a command exists
command_exists() {
    command -v "$1" &>/dev/null
}

# Resolve architecture name for downloads
arch_resolve() {
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l)  echo "armv7" ;;
        *)       echo "$arch" ;;
    esac
}

# ==============================================================================
# SECTION 5: PACKAGE MANAGEMENT
# ==============================================================================

# Install a package if not already installed
ensure_package() {
    local pkg="$1"
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
        msg_info "Installing ${pkg}..."
        apt-get install -y "$pkg" > /dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            msg_ok "${pkg} installed"
        else
            msg_error "Failed to install ${pkg}"
            return 1
        fi
    fi
    return 0
}

# ==============================================================================
# SECTION 6: TRANSLATION SUPPORT
# ==============================================================================

DEBMENUX_LANG="${DEBMENUX_LANG:-es}"
declare -A __TRANSLATIONS

load_language() {
    local lang_file="${DEBMENUX_BASE_DIR:-/usr/local/share/debmenux}/lang/${DEBMENUX_LANG}.json"

    if [[ ! -f "$lang_file" ]]; then
        # Fallback: no translation, use raw strings
        return 1
    fi

    # Load translations into associative array
    while IFS="=" read -r key value; do
        __TRANSLATIONS["$key"]="$value"
    done < <(jq -r 'to_entries[] | "\(.key)=\(.value)"' "$lang_file" 2>/dev/null)

    return 0
}

translate() {
    local key="$1"
    if [[ -n "${__TRANSLATIONS[$key]+x}" ]]; then
        echo "${__TRANSLATIONS[$key]}"
    else
        echo "$key"
    fi
}

# Alias corto
t() { translate "$@"; }

# ==============================================================================
# SECTION 7: INPUT & VALIDATION
# ==============================================================================

# Ask yes/no question (default yes)
confirm() {
    local msg="${1:-Continue?}"
    local default="${2:-y}"
    local prompt

    if [[ "$default" == "y" ]]; then
        prompt="${msg} [Y/n]: "
    else
        prompt="${msg} [y/N]: "
    fi

    read -rp "$(echo -e "${TAB}${BL}?${CL} ${prompt}")" answer
    answer="${answer:-$default}"

    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" ]]
}

# Validate that a variable is not empty
require_var() {
    local var_name="$1"
    local var_value="$2"
    if [[ -z "$var_value" ]]; then
        msg_error "Required variable ${var_name} is empty!"
        return 1
    fi
    return 0
}

# ==============================================================================
# SECTION 8: CLEANUP
# ==============================================================================

cleanup_on_exit() {
    stop_spinner
}

trap cleanup_on_exit EXIT
