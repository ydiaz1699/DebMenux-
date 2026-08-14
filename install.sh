#!/usr/bin/env bash
# ==========================================================
# DebMenux — Toolkit interactivo para homelab Debian + Docker
# ==========================================================
# Archivo: install.sh
# Descripción: Instalador one-liner. Descarga e instala
#              DebMenux en cualquier sistema basado en Debian.
#
# Uso:
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/ydiaz1699/DebMenux-/main/install.sh)"
#
# Licencia: MIT
# ==========================================================

# No usar set -euo pipefail en instaladores — manejar errores explícitamente

# Configuración
REPO_URL="https://github.com/ydiaz1699/DebMenux-.git"
BASE_DIR="/debmenux"
INSTALL_DIR="/usr/local/bin"
CONFIG_FILE="${BASE_DIR}/config.json"
MENU_CMD="debmenu"
VERSION="0.1.0"
DEBMENUX_LANG="es"
DEBMENUX_CONF=""

# Colores (inline porque lib/utils.sh aún no está disponible)
GN="\033[1;92m"
RD="\033[01;31m"
YW="\033[33m"
YWB="\033[1;33m"
BL="\033[36m"
BOLD="\033[1m"
CL="\033[m"
TAB="    "
CM="${GN}✅${CL}"
CROSS="${RD}❌${CL}"

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
    echo -ne "${TAB}⚙️  ${YW}${1}${CL}"
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
    echo -e "${TAB}⚠️  ${YWB}${1}${CL}"
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
    echo -e "${TAB}${BOLD}${BL}║${CL}    ${BOLD}Toolkit interactivo para${CL}           ${BOLD}${BL}║${CL}"
    echo -e "${TAB}${BOLD}${BL}║${CL}    ${BOLD}homelab Debian + Docker${CL}            ${BOLD}${BL}║${CL}"
    echo -e "${TAB}${BOLD}${BL}║${CL}                                      ${BOLD}${BL}║${CL}"
    echo -e "${TAB}${BOLD}${BL}╚══════════════════════════════════════╝${CL}"
    echo -e ""
}

# ==============================================================================
# VERIFICACIONES PREVIAS
# ==============================================================================

preflight_checks() {
    # Debe ser root
    if [[ "$(id -u)" -ne 0 ]]; then
        msg_error "Este script debe ejecutarse como root."
        echo -e "${TAB}Ejecuta: ${YWB}sudo bash install.sh${CL}"
        exit 1
    fi

    # Debe ser sistema basado en Debian
    if [[ ! -f /etc/debian_version ]]; then
        msg_error "Este toolkit requiere un sistema basado en Debian."
        exit 1
    fi

    # Verificar conectividad a internet
    if ! ping -c 1 -W 3 github.com &>/dev/null; then
        msg_error "Sin conexión a internet. No se puede alcanzar github.com."
        exit 1
    fi

    msg_ok "Verificaciones previas pasadas 🛡️"
}

# ==============================================================================
# SELECCIÓN DE IDIOMA
# ==============================================================================

select_language() {
    if command -v dialog &>/dev/null; then
        local lang
        lang=$(dialog --clear --backtitle "DebMenux — Instalador" \
            --title " 🌐 Seleccionar Idioma " \
            --menu "\nElige tu idioma:" 12 50 4 \
            "es" "🇪🇸 Español" \
            "en" "🇬🇧 English" \
            3>&1 1>&2 2>&3) || lang="es"
        clear
        DEBMENUX_LANG="$lang"
    else
        echo -e "${TAB}${BL}🌐${CL} Seleccionar idioma:"
        echo -e "${TAB}  1) 🇪🇸 Español (por defecto)"
        echo -e "${TAB}  2) 🇬🇧 English"
        local choice=""
        read -rp "$(echo -e "${TAB}  → ")" choice || true
        case "${choice:-1}" in
            2) DEBMENUX_LANG="en" ;;
            *) DEBMENUX_LANG="es" ;;
        esac
    fi

    msg_ok "Idioma: ${DEBMENUX_LANG} 🌐"
}

# ==============================================================================
# INSTALAR DEPENDENCIAS
# ==============================================================================

install_dependencies() {
    msg_info "Actualizando listas de paquetes"
    apt-get update -qq > /dev/null 2>&1 || true
    msg_ok "Listas de paquetes actualizadas 📦"

    local deps=("dialog" "curl" "jq" "git")

    for pkg in "${deps[@]}"; do
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            msg_info "Instalando ${pkg}"
            apt-get install -y "$pkg" > /dev/null 2>&1
            if [[ $? -eq 0 ]]; then
                msg_ok "${pkg} instalado"
            else
                msg_error "No se pudo instalar ${pkg}"
                exit 1
            fi
        fi
    done

    msg_ok "Todas las dependencias satisfechas 📦"
}

# ==============================================================================
# INSTALAR DOCKER (si no está presente)
# ==============================================================================

install_docker() {
    if command -v docker &>/dev/null; then
        local docker_ver
        docker_ver=$(docker --version | grep -oP '\d+\.\d+\.\d+')
        msg_ok "Docker ya instalado (v${docker_ver}) 🐳"
        return 0
    fi

    if ! confirm_install_docker; then
        msg_warn "Docker no instalado. Los scripts de servicios no funcionarán sin Docker."
        return 0
    fi

    msg_info "Instalando Docker vía script oficial"
    curl -fsSL https://get.docker.com | sh > /dev/null 2>&1
    if [[ $? -eq 0 ]]; then
        systemctl enable --now docker > /dev/null 2>&1
        msg_ok "Docker instalado e iniciado 🐳"
    else
        msg_error "La instalación de Docker falló"
        msg_warn "Instala manualmente: https://docs.docker.com/engine/install/debian/"
        return 1
    fi
}

confirm_install_docker() {
    echo -e ""
    echo -e "${TAB}${YWB}⚠️  Docker no está instalado.${CL}"
    echo -e "${TAB}DebMenux necesita Docker para gestionar servicios."
    echo -e ""
    read -rp "$(echo -e "${TAB}${BL}?${CL} ¿Instalar Docker ahora? [S/n]: ")" answer
    answer="${answer:-s}"
    [[ "${answer,,}" == "s" || "${answer,,}" == "si" || "${answer,,}" == "sí" || "${answer,,}" == "y" ]]
}

# ==============================================================================
# CLONAR E INSTALAR ARCHIVOS
# ==============================================================================

install_files() {
    msg_info "Clonando repositorio DebMenux en ${BASE_DIR}"

    # Si ya existe, actualizar en vez de clonar
    if [[ -d "${BASE_DIR}/.git" ]]; then
        msg_warn "DebMenux ya existe en ${BASE_DIR}, actualizando..."
        git -C "$BASE_DIR" pull --ff-only > /dev/null 2>&1 || {
            msg_error "No se pudo actualizar. Resuelve conflictos manualmente."
            exit 1
        }
        msg_ok "Repositorio actualizado (git pull) 📥"
    else
        # Clonar directamente en /debmenux
        if [[ -d "$BASE_DIR" ]]; then
            msg_warn "Directorio ${BASE_DIR} existe pero no es git. Respaldando..."
            mv "$BASE_DIR" "${BASE_DIR}.bak.$(date +%s)"
        fi
        git clone "$REPO_URL" "$BASE_DIR" > /dev/null 2>&1
        if [[ $? -ne 0 ]]; then
            msg_error "No se pudo clonar el repositorio"
            exit 1
        fi
        msg_ok "Repositorio clonado en ${BASE_DIR} 📥"
    fi

    # Hacer ejecutables todos los .sh
    find "${BASE_DIR}" -type f -name '*.sh' -exec chmod +x {} +

    # Crear symlink del comando en /usr/local/bin
    msg_info "Creando comando '${MENU_CMD}'"
    ln -sf "${BASE_DIR}/menu" "${INSTALL_DIR}/${MENU_CMD}"
    chmod +x "${BASE_DIR}/menu"
    msg_ok "Comando '${MENU_CMD}' disponible globalmente 🔗"

    # Crear config si no existe
    if [[ ! -f "$CONFIG_FILE" ]]; then
        # Detectar config de integración para leer DOCKER_DIR
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
            msg_ok "Config de integración detectada: ${integration_conf} 🔗"
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
        msg_ok "Configuración creada (docker_dir: ${detected_docker_dir}) ⚙️"
    fi
}

# ==============================================================================
# POST-INSTALACIÓN
# ==============================================================================

show_post_install() {
    echo -e ""
    echo -e "${TAB}${BOLD}${GN}━━━ 🚀 Instalación completada ━━━${CL}"
    echo -e ""
    echo -e "${TAB}${BOLD}Para lanzar DebMenux:${CL}"
    echo -e "${TAB}  ${YWB}${MENU_CMD}${CL}"
    echo -e ""
    echo -e "${TAB}${BOLD}Para instalar un servicio directamente:${CL}"
    echo -e "${TAB}  ${YWB}${MENU_CMD} install <servicio>${CL}"
    echo -e ""
    echo -e "${TAB}${BOLD}Ejemplos:${CL}"
    echo -e "${TAB}  📦 ${MENU_CMD} install adguard"
    echo -e "${TAB}  📦 ${MENU_CMD} install emqx"
    echo -e "${TAB}  📋 ${MENU_CMD} list"
    echo -e "${TAB}  📊 ${MENU_CMD} status"
    echo -e ""

    local server_ip
    server_ip=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+' || hostname -I | awk '{print $1}')
    echo -e "${TAB}${BOLD}🌐 IP del servidor:${CL} ${BL}${server_ip:-localhost}${CL}"
    echo -e ""
}

# ==============================================================================
# PRINCIPAL
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
