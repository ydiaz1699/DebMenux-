#!/usr/bin/env bash
# ==========================================================
# DebMenux — Toolkit interactivo para homelab Debian + Docker
# ==========================================================
# Archivo: lib/docker.sh
# Descripción: Helpers de Docker Compose para gestión de servicios.
# Licencia: MIT
# ==========================================================

[[ -n "${__DEBMENUX_DOCKER_LOADED:-}" ]] && return 0
__DEBMENUX_DOCKER_LOADED=1

# ==============================================================================
# SECCIÓN 1: CONFIGURACIÓN
# ==============================================================================

# Directorio base de Docker Compose (configurable por usuario)
DOCKER_DIR="${DOCKER_DIR:-/docker}"

# ==============================================================================
# SECCIÓN 1.5: ENTORNO GLOBAL
# ==============================================================================

# Cargar .env compartido (SERVER_IP, TZ) del directorio Docker base
# o desde la ruta especificada en debmenux.conf vía integration.sh.
# Se llama temprano para que los scripts hereden TZ, SERVER_IP, etc.
_load_docker_global_env() {
    local env_file="${DOCKER_DIR}/.env"
    [[ -f "$env_file" ]] || return 0

    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        # Solo exportar vars globales conocidas, no sobreescribir existentes
        case "$key" in
            SERVER_IP|TZ|PUID|PGID)
                [[ -z "${!key:-}" ]] && export "$key=$value"
                ;;
        esac
    done < "$env_file"
}

_load_docker_global_env

# ==============================================================================
# SECCIÓN 2: PREREQUISITOS
# ==============================================================================

# Verificar que Docker está instalado y corriendo
check_docker() {
    if ! command_exists docker; then
        msg_error "Docker no está instalado."
        msg_warn "Ejecuta: debmenu → Post-Instalación → Instalar Docker"
        return 1
    fi

    if ! systemctl is-active --quiet docker; then
        msg_error "El demonio Docker no está corriendo."
        msg_warn "Ejecuta: systemctl start docker"
        return 1
    fi

    return 0
}

# Verificar docker compose (plugin v2)
check_compose() {
    if ! docker compose version &>/dev/null; then
        msg_error "El plugin Docker Compose no está instalado."
        msg_warn "Instala con: apt-get install docker-compose-plugin"
        return 1
    fi
    return 0
}

# ==============================================================================
# SECCIÓN 3: CICLO DE VIDA DE SERVICIOS
# ==============================================================================

# Iniciar un servicio
svc_up() {
    local svc_name="$1"
    local svc_dir="${DOCKER_DIR}/${svc_name}"

    if [[ ! -f "${svc_dir}/compose.yml" ]]; then
        msg_error "No se encontró compose.yml para '${svc_name}'"
        return 1
    fi

    msg_info "Iniciando ${svc_name}..."
    docker compose -f "${svc_dir}/compose.yml" up -d 2>&1 | tail -5
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        msg_ok "${svc_name} iniciado 🟢"
    else
        msg_error "Error al iniciar ${svc_name}"
        return 1
    fi
}

# Detener un servicio
svc_down() {
    local svc_name="$1"
    local svc_dir="${DOCKER_DIR}/${svc_name}"

    if [[ ! -f "${svc_dir}/compose.yml" ]]; then
        msg_error "No se encontró compose.yml para '${svc_name}'"
        return 1
    fi

    msg_info "Deteniendo ${svc_name}..."
    docker compose -f "${svc_dir}/compose.yml" down 2>&1 | tail -5
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        msg_ok "${svc_name} detenido 🔴"
    else
        msg_error "Error al detener ${svc_name}"
        return 1
    fi
}

# Reiniciar un servicio
svc_restart() {
    local svc_name="$1"
    local svc_dir="${DOCKER_DIR}/${svc_name}"

    if [[ ! -f "${svc_dir}/compose.yml" ]]; then
        msg_error "No se encontró compose.yml para '${svc_name}'"
        return 1
    fi

    msg_info "Reiniciando ${svc_name}..."
    docker compose -f "${svc_dir}/compose.yml" restart 2>&1 | tail -5
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        msg_ok "${svc_name} reiniciado 🔄"
    else
        msg_error "Error al reiniciar ${svc_name}"
        return 1
    fi
}

# Ver logs
svc_logs() {
    local svc_name="$1"
    local lines="${2:-50}"
    local svc_dir="${DOCKER_DIR}/${svc_name}"

    if [[ ! -f "${svc_dir}/compose.yml" ]]; then
        msg_error "No se encontró compose.yml para '${svc_name}'"
        return 1
    fi

    docker compose -f "${svc_dir}/compose.yml" logs --tail="$lines"
}

# Descargar imágenes más recientes
svc_pull() {
    local svc_name="$1"
    local svc_dir="${DOCKER_DIR}/${svc_name}"

    if [[ ! -f "${svc_dir}/compose.yml" ]]; then
        msg_error "No se encontró compose.yml para '${svc_name}'"
        return 1
    fi

    msg_info "Descargando imágenes de ${svc_name}..."
    docker compose -f "${svc_dir}/compose.yml" pull 2>&1 | tail -5
    msg_ok "Imágenes descargadas para ${svc_name} 📥"
}

# Actualizar un servicio (pull + recrear)
svc_update() {
    local svc_name="$1"
    local svc_dir="${DOCKER_DIR}/${svc_name}"

    if [[ ! -f "${svc_dir}/compose.yml" ]]; then
        msg_error "No se encontró compose.yml para '${svc_name}'"
        return 1
    fi

    msg_info "Actualizando ${svc_name}..."
    docker compose -f "${svc_dir}/compose.yml" pull 2>&1 | tail -3
    docker compose -f "${svc_dir}/compose.yml" up -d --force-recreate 2>&1 | tail -3
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        msg_ok "${svc_name} actualizado 🆙"
    else
        msg_error "Error al actualizar ${svc_name}"
        return 1
    fi
}

# ==============================================================================
# SECCIÓN 4: DESCUBRIMIENTO DE SERVICIOS
# ==============================================================================

# Listar todos los servicios instalados (directorios con compose.yml)
list_services() {
    local services=()
    for dir in "${DOCKER_DIR}"/*/; do
        if [[ -f "${dir}compose.yml" ]]; then
            services+=("$(basename "$dir")")
        fi
    done
    printf '%s\n' "${services[@]}"
}

# Verificar si un servicio está corriendo
svc_is_running() {
    local svc_name="$1"
    local svc_dir="${DOCKER_DIR}/${svc_name}"

    if [[ ! -f "${svc_dir}/compose.yml" ]]; then
        return 1
    fi

    local running
    running=$(docker compose -f "${svc_dir}/compose.yml" ps --status running -q 2>/dev/null | wc -l)
    [[ "$running" -gt 0 ]]
}

# Obtener estado del servicio (contenedores corriendo / total)
svc_status() {
    local svc_name="$1"
    local svc_dir="${DOCKER_DIR}/${svc_name}"

    if [[ ! -f "${svc_dir}/compose.yml" ]]; then
        echo "no instalado"
        return
    fi

    local running total
    running=$(docker compose -f "${svc_dir}/compose.yml" ps --status running -q 2>/dev/null | wc -l)
    total=$(docker compose -f "${svc_dir}/compose.yml" ps -q 2>/dev/null | wc -l)

    if [[ "$total" -eq 0 ]]; then
        echo "🔴 detenido"
    elif [[ "$running" -eq "$total" ]]; then
        echo "🟢 corriendo (${running}/${total})"
    else
        echo "🟡 degradado (${running}/${total})"
    fi
}

# ==============================================================================
# SECCIÓN 5: HELPERS DE RED
# ==============================================================================

# Crear una red Docker si no existe
ensure_network() {
    local net_name="$1"
    local subnet="${2:-}"
    local driver="${3:-bridge}"

    if ! docker network inspect "$net_name" &>/dev/null; then
        msg_info "Creando red '${net_name}'..."
        local cmd="docker network create --driver ${driver}"
        [[ -n "$subnet" ]] && cmd+=" --subnet=${subnet}"
        cmd+=" ${net_name}"
        eval "$cmd" >/dev/null 2>&1
        msg_ok "Red '${net_name}' creada 🌐"
    fi
}

# ==============================================================================
# SECCIÓN 6: SEGURIDAD POR DEFECTO
# ==============================================================================

# Generar contraseña aleatoria
generate_password() {
    local length="${1:-24}"
    openssl rand -base64 "$length" | tr -d '/+=' | head -c "$length"
}

# Generar token hexadecimal
generate_token() {
    local length="${1:-32}"
    openssl rand -hex "$length"
}

# Establecer permisos restrictivos en archivo .env
secure_env() {
    local env_file="$1"
    chmod 600 "$env_file"
    msg_ok "Permisos asegurados: ${env_file} (600) 🔒"
}
