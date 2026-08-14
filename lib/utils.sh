#!/usr/bin/env bash
# ==========================================================
# DebMenux — Toolkit interactivo para homelab Debian + Docker
# ==========================================================
# Archivo: lib/utils.sh
# Descripción: Funciones utilitarias — colores, spinners,
#              mensajes con emojis, traducciones y helpers.
# Licencia: MIT
# ==========================================================

# Evitar doble source
[[ -n "${__DEBMENUX_UTILS_LOADED:-}" ]] && return 0
__DEBMENUX_UTILS_LOADED=1

# ==============================================================================
# SECCIÓN 1: COLORES Y ESTILOS
# ==============================================================================

# Reset
CL="\033[m"
RESET="\033[0m"

# Colores
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

# Símbolos con emojis
CM="${GN}✅${CL}"
CROSS="${RD}❌${CL}"
ARROW="${BL}➜${CL}"
INFO_ICON="${BL}ℹ️${CL}"
WARN_ICON="${ORANGE}⚠️${CL}"
ROCKET="🚀"
PACKAGE="📦"
GEAR="⚙️"
SHIELD="🛡️"
NETWORK="🌐"
DISK="💾"
KEY="🔑"
CHECK="✅"
FIRE="🔥"
WRENCH="🔧"
CLOCK="⏱️"
TAB="    "
HOLD="-"
BFR="\\r\\033[K"

# ==============================================================================
# SECCIÓN 2: SPINNER
# ==============================================================================

SPINNER_PID=""

spinner() {
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local spin_i=0
    local interval=0.1
    local color="${YW}"

    printf "\e[?25l"  # Ocultar cursor

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
    printf "\r\033[K"   # Limpiar línea
    printf "\e[?25h"    # Mostrar cursor
    SPINNER_PID=""
}

# ==============================================================================
# SECCIÓN 3: FUNCIONES DE MENSAJE (con emojis)
# ==============================================================================

msg_info() {
    local msg="$1"
    echo -ne "${TAB}${GEAR} ${YW}${msg}${CL}"
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
    echo -e "${BFR}${TAB}${ROCKET} ${BOLD}${GN}${msg}${CL}\n"
}

# Separador visual
msg_separator() {
    echo -e "${TAB}${DARK_GRAY}────────────────────────────────────────${CL}"
}

# ==============================================================================
# SECCIÓN 4: HELPERS DEL SISTEMA
# ==============================================================================

# Verificar que se ejecuta como root
check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        msg_error "Este script debe ejecutarse como root (sudo)."
        exit 1
    fi
}

# Obtener la IP principal del servidor
get_server_ip() {
    local ip
    ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+')
    [[ -z "$ip" ]] && ip=$(hostname -I | awk '{print $1}')
    [[ -z "$ip" ]] && ip="localhost"
    echo "$ip"
}

# Verificar si un comando existe
command_exists() {
    command -v "$1" &>/dev/null
}

# Resolver nombre de arquitectura para descargas
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
# SECCIÓN 5: GESTIÓN DE PAQUETES
# ==============================================================================

# Instalar paquete si no está presente
ensure_package() {
    local pkg="$1"
    if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
        msg_info "Instalando ${pkg}..."
        apt-get install -y "$pkg" > /dev/null 2>&1
        if [[ $? -eq 0 ]]; then
            msg_ok "${pkg} instalado"
        else
            msg_error "No se pudo instalar ${pkg}"
            return 1
        fi
    fi
    return 0
}

# ==============================================================================
# SECCIÓN 6: SOPORTE DE TRADUCCIONES
# ==============================================================================

DEBMENUX_LANG="${DEBMENUX_LANG:-es}"
declare -A __TRANSLATIONS

load_language() {
    local lang_file="${DEBMENUX_BASE_DIR:-/debmenux}/lang/${DEBMENUX_LANG}.json"

    if [[ ! -f "$lang_file" ]]; then
        return 1
    fi

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
# SECCIÓN 7: ENTRADA Y VALIDACIÓN
# ==============================================================================

# Pregunta sí/no (por defecto sí)
confirm() {
    local msg="${1:-¿Continuar?}"
    local default="${2:-y}"
    local prompt

    if [[ "$default" == "y" ]]; then
        prompt="${msg} [S/n]: "
    else
        prompt="${msg} [s/N]: "
    fi

    read -rp "$(echo -e "${TAB}${BL}?${CL} ${prompt}")" answer
    answer="${answer:-$default}"

    [[ "${answer,,}" == "y" || "${answer,,}" == "yes" || "${answer,,}" == "s" || "${answer,,}" == "si" || "${answer,,}" == "sí" ]]
}

# Validar que una variable no esté vacía
require_var() {
    local var_name="$1"
    local var_value="$2"
    if [[ -z "$var_value" ]]; then
        msg_error "La variable requerida ${var_name} está vacía."
        return 1
    fi
    return 0
}

# ==============================================================================
# SECCIÓN 8: LIMPIEZA
# ==============================================================================

cleanup_on_exit() {
    stop_spinner
}

trap cleanup_on_exit EXIT
