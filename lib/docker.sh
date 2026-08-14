#!/usr/bin/env bash
# ==========================================================
# DebMenux - Menu-driven toolkit for Debian homelab/NAS
# ==========================================================
# File: lib/docker.sh
# Description: Docker Compose helpers for service management.
# License: MIT
# ==========================================================

[[ -n "${__DEBMENUX_DOCKER_LOADED:-}" ]] && return 0
__DEBMENUX_DOCKER_LOADED=1

# ==============================================================================
# SECTION 1: CONFIGURATION
# ==============================================================================

# Docker compose base directory (user-configurable)
DOCKER_DIR="${DOCKER_DIR:-/docker}"

# ==============================================================================
# SECTION 2: PREREQUISITES
# ==============================================================================

# Ensure Docker is installed and running
check_docker() {
    if ! command_exists docker; then
        msg_error "Docker is not installed."
        msg_warn "Run: menu → Post-Install → Install Docker"
        return 1
    fi

    if ! systemctl is-active --quiet docker; then
        msg_error "Docker daemon is not running."
        msg_warn "Run: systemctl start docker"
        return 1
    fi

    return 0
}

# Ensure docker compose (v2 plugin) is available
check_compose() {
    if ! docker compose version &>/dev/null; then
        msg_error "Docker Compose plugin is not installed."
        msg_warn "Install with: apt-get install docker-compose-plugin"
        return 1
    fi
    return 0
}

# ==============================================================================
# SECTION 3: SERVICE LIFECYCLE
# ==============================================================================

# Start a service
svc_up() {
    local svc_name="$1"
    local svc_dir="${DOCKER_DIR}/${svc_name}"

    if [[ ! -f "${svc_dir}/compose.yml" ]]; then
        msg_error "No compose.yml found for '${svc_name}'"
        return 1
    fi

    msg_info "Starting ${svc_name}..."
    docker compose -f "${svc_dir}/compose.yml" up -d 2>&1 | tail -5
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        msg_ok "${svc_name} started"
    else
        msg_error "Failed to start ${svc_name}"
        return 1
    fi
}

# Stop a service
svc_down() {
    local svc_name="$1"
    local svc_dir="${DOCKER_DIR}/${svc_name}"

    if [[ ! -f "${svc_dir}/compose.yml" ]]; then
        msg_error "No compose.yml found for '${svc_name}'"
        return 1
    fi

    msg_info "Stopping ${svc_name}..."
    docker compose -f "${svc_dir}/compose.yml" down 2>&1 | tail -5
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        msg_ok "${svc_name} stopped"
    else
        msg_error "Failed to stop ${svc_name}"
        return 1
    fi
}

# Restart a service
svc_restart() {
    local svc_name="$1"
    local svc_dir="${DOCKER_DIR}/${svc_name}"

    if [[ ! -f "${svc_dir}/compose.yml" ]]; then
        msg_error "No compose.yml found for '${svc_name}'"
        return 1
    fi

    msg_info "Restarting ${svc_name}..."
    docker compose -f "${svc_dir}/compose.yml" restart 2>&1 | tail -5
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        msg_ok "${svc_name} restarted"
    else
        msg_error "Failed to restart ${svc_name}"
        return 1
    fi
}

# View logs
svc_logs() {
    local svc_name="$1"
    local lines="${2:-50}"
    local svc_dir="${DOCKER_DIR}/${svc_name}"

    if [[ ! -f "${svc_dir}/compose.yml" ]]; then
        msg_error "No compose.yml found for '${svc_name}'"
        return 1
    fi

    docker compose -f "${svc_dir}/compose.yml" logs --tail="$lines"
}

# Pull latest images
svc_pull() {
    local svc_name="$1"
    local svc_dir="${DOCKER_DIR}/${svc_name}"

    if [[ ! -f "${svc_dir}/compose.yml" ]]; then
        msg_error "No compose.yml found for '${svc_name}'"
        return 1
    fi

    msg_info "Pulling images for ${svc_name}..."
    docker compose -f "${svc_dir}/compose.yml" pull 2>&1 | tail -5
    msg_ok "Images pulled for ${svc_name}"
}

# Update a service (pull + recreate)
svc_update() {
    local svc_name="$1"
    local svc_dir="${DOCKER_DIR}/${svc_name}"

    if [[ ! -f "${svc_dir}/compose.yml" ]]; then
        msg_error "No compose.yml found for '${svc_name}'"
        return 1
    fi

    msg_info "Updating ${svc_name}..."
    docker compose -f "${svc_dir}/compose.yml" pull 2>&1 | tail -3
    docker compose -f "${svc_dir}/compose.yml" up -d --force-recreate 2>&1 | tail -3
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        msg_ok "${svc_name} updated"
    else
        msg_error "Failed to update ${svc_name}"
        return 1
    fi
}

# ==============================================================================
# SECTION 4: SERVICE DISCOVERY
# ==============================================================================

# List all installed services (directories with compose.yml)
list_services() {
    local services=()
    for dir in "${DOCKER_DIR}"/*/; do
        if [[ -f "${dir}compose.yml" ]]; then
            services+=("$(basename "$dir")")
        fi
    done
    printf '%s\n' "${services[@]}"
}

# Check if a service is running
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

# Get service status (running containers / total containers)
svc_status() {
    local svc_name="$1"
    local svc_dir="${DOCKER_DIR}/${svc_name}"

    if [[ ! -f "${svc_dir}/compose.yml" ]]; then
        echo "not installed"
        return
    fi

    local running total
    running=$(docker compose -f "${svc_dir}/compose.yml" ps --status running -q 2>/dev/null | wc -l)
    total=$(docker compose -f "${svc_dir}/compose.yml" ps -q 2>/dev/null | wc -l)

    if [[ "$total" -eq 0 ]]; then
        echo "stopped"
    elif [[ "$running" -eq "$total" ]]; then
        echo "running (${running}/${total})"
    else
        echo "degraded (${running}/${total})"
    fi
}

# ==============================================================================
# SECTION 5: NETWORK HELPERS
# ==============================================================================

# Create a docker network if it doesn't exist
ensure_network() {
    local net_name="$1"
    local subnet="${2:-}"
    local driver="${3:-bridge}"

    if ! docker network inspect "$net_name" &>/dev/null; then
        msg_info "Creating network '${net_name}'..."
        local cmd="docker network create --driver ${driver}"
        [[ -n "$subnet" ]] && cmd+=" --subnet=${subnet}"
        cmd+=" ${net_name}"
        eval "$cmd" >/dev/null 2>&1
        msg_ok "Network '${net_name}' created"
    fi
}

# ==============================================================================
# SECTION 6: SECURITY DEFAULTS
# ==============================================================================

# Generate a random password
generate_password() {
    local length="${1:-24}"
    openssl rand -base64 "$length" | tr -d '/+=' | head -c "$length"
}

# Generate a hex token
generate_token() {
    local length="${1:-32}"
    openssl rand -hex "$length"
}

# Set restrictive permissions on .env file
secure_env() {
    local env_file="$1"
    chmod 600 "$env_file"
    msg_ok "Secured ${env_file} (600)"
}
