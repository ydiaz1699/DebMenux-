#!/usr/bin/env bash
# ==========================================================
# DebMenux - Menu-driven toolkit for Debian homelab/NAS
# ==========================================================
# File: lib/integration.sh
# Description: Integration layer between DebMenux and external
#              configuration repos (e.g. nas-dotfiles).
#
# This module is OPTIONAL — DebMenux works fully standalone.
# When a debmenux.conf is found, it enables:
#   - Auto-registration of installed services to the catalog
#   - Loading global .env variables (SERVER_IP, TZ)
#   - Reading user-specific paths (not hardcoded)
#
# Detection order for debmenux.conf:
#   1. $DEBMENUX_CONF (explicit env var)
#   2. /etc/debmenux/debmenux.conf (system-wide)
#   3. $HOME/.config/debmenux/debmenux.conf (user-level)
#   4. Auto-discovery: find a repo with .debmenux-integration marker
#
# License: MIT
# ==========================================================

[[ -n "${__DEBMENUX_INTEGRATION_LOADED:-}" ]] && return 0
__DEBMENUX_INTEGRATION_LOADED=1

# ==============================================================================
# SECTION 1: CONFIGURATION DISCOVERY
# ==============================================================================

# Path to the integration config (set after detection)
DEBMENUX_CONF="${DEBMENUX_CONF:-}"

# Detected paths (populated by load_integration_config)
INTEGRATION_ENABLED=false
INTEGRATION_DOTFILES_DIR=""
INTEGRATION_CATALOG_DIR=""
INTEGRATION_GLOBAL_ENV=""
INTEGRATION_DOCKER_DIR=""

# Locate and load debmenux.conf
load_integration_config() {
    # Search order
    local search_paths=(
        "${DEBMENUX_CONF}"
        "/etc/debmenux/debmenux.conf"
        "${HOME}/.config/debmenux/debmenux.conf"
    )

    for conf_path in "${search_paths[@]}"; do
        if [[ -n "$conf_path" && -f "$conf_path" ]]; then
            DEBMENUX_CONF="$conf_path"
            break
        fi
    done

    # Not found — integration disabled (this is fine, DebMenux works standalone)
    if [[ -z "$DEBMENUX_CONF" || ! -f "$DEBMENUX_CONF" ]]; then
        INTEGRATION_ENABLED=false
        return 0
    fi

    # Parse the config file (simple KEY=VALUE, no eval for safety)
    while IFS='=' read -r key value; do
        # Skip comments and empty lines
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue

        # Trim whitespace
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Expand ~ and $HOME in value
        value="${value/#\~/$HOME}"
        value="${value/\$HOME/$HOME}"

        case "$key" in
            DOTFILES_DIR)     INTEGRATION_DOTFILES_DIR="$value" ;;
            CATALOG_DIR)      INTEGRATION_CATALOG_DIR="$value" ;;
            GLOBAL_ENV)       INTEGRATION_GLOBAL_ENV="$value" ;;
            DOCKER_DIR)       INTEGRATION_DOCKER_DIR="$value" ;;
        esac
    done < "$DEBMENUX_CONF"

    # Validate minimum requirement
    if [[ -n "$INTEGRATION_DOTFILES_DIR" && -d "$INTEGRATION_DOTFILES_DIR" ]]; then
        INTEGRATION_ENABLED=true

        # Apply DOCKER_DIR from integration config if not already set by CLI
        if [[ -n "$INTEGRATION_DOCKER_DIR" && "$DOCKER_DIR" == "/docker" ]]; then
            DOCKER_DIR="$INTEGRATION_DOCKER_DIR"
        fi

        # Default catalog path if not specified
        if [[ -z "$INTEGRATION_CATALOG_DIR" ]]; then
            INTEGRATION_CATALOG_DIR="${INTEGRATION_DOTFILES_DIR}/agent/catalog/services"
        fi

        # Default global env path if not specified
        if [[ -z "$INTEGRATION_GLOBAL_ENV" && -n "$INTEGRATION_DOCKER_DIR" ]]; then
            INTEGRATION_GLOBAL_ENV="${INTEGRATION_DOCKER_DIR}/.env"
        fi
    fi

    return 0
}

# ==============================================================================
# SECTION 2: GLOBAL ENVIRONMENT
# ==============================================================================

# Load global .env file (SERVER_IP, TZ, etc.) if integration is enabled
load_global_env() {
    local env_file="${INTEGRATION_GLOBAL_ENV:-${DOCKER_DIR}/.env}"

    if [[ ! -f "$env_file" ]]; then
        return 0
    fi

    # Export only safe variables (no commands, no special chars)
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Only export uppercase vars that look like config
        if [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
            export "$key=$value"
        fi
    done < "$env_file"
}

# ==============================================================================
# SECTION 3: CATALOG REGISTRATION
# ==============================================================================

# Register an installed service to the nas-dotfiles catalog.
# Called at the end of each service install script.
#
# Usage: register_to_catalog
#
# Requires these variables to be set by the service script:
#   APP, APP_ID, CATEGORY, IMAGE, var_cpu, var_ram
#   PORT_WEB (or specific port vars)
#   NETWORKS (array, optional)
#
# What it creates:
#   $CATALOG_DIR/<APP_ID>/ficha.md      — service metadata
#   $CATALOG_DIR/<APP_ID>/compose.yml   — copy of installed compose
#   $CATALOG_DIR/<APP_ID>/.env.example  — sanitized env template
#
register_to_catalog() {
    # Skip if integration is not enabled
    if [[ "$INTEGRATION_ENABLED" != "true" ]]; then
        return 0
    fi

    local catalog_dir="${INTEGRATION_CATALOG_DIR}"

    # Validate catalog directory exists
    if [[ ! -d "$catalog_dir" ]]; then
        # Try to create it (might be first service)
        mkdir -p "$catalog_dir" 2>/dev/null || return 0
    fi

    local svc_dir="${DOCKER_DIR}/${APP_ID}"
    local target_dir="${catalog_dir}/${APP_ID}"

    msg_info "Registering ${APP} to catalog"

    # Create catalog entry directory
    mkdir -p "$target_dir"

    # ── Generate ficha.md ─────────────────────────────────────
    _generate_ficha "$target_dir"

    # ── Copy compose.yml ──────────────────────────────────────
    if [[ -f "${svc_dir}/compose.yml" ]]; then
        cp "${svc_dir}/compose.yml" "${target_dir}/compose.yml"
    fi

    # ── Generate .env.example (secrets replaced) ──────────────
    _generate_env_example "$target_dir" "$svc_dir"

    msg_ok "${APP} registered to catalog (${target_dir})"
}

# Generate ficha.md for a service
_generate_ficha() {
    local target_dir="$1"

    # Determine ports
    local port_main="${PORT_WEB:-${PORT_MQTT:-${PORT_ADMIN:-0}}}"

    # Determine networks
    local networks_yaml=""
    if [[ ${#NETWORKS[@]:-0} -gt 0 ]]; then
        networks_yaml=$(printf "  - %s\n" "${NETWORKS[@]}")
    fi

    # Determine volumes from compose (if it exists already)
    local volumes_yaml=""
    if [[ -f "${DOCKER_DIR}/${APP_ID}/compose.yml" ]]; then
        volumes_yaml=$(grep -E "^\s+- \./.*:.*" "${DOCKER_DIR}/${APP_ID}/compose.yml" 2>/dev/null | sed 's/^[[:space:]]*/  /' || true)
    fi

    # Extract env_required from .env (non-comment, non-empty keys)
    local env_list=""
    if [[ -f "${DOCKER_DIR}/${APP_ID}/.env" ]]; then
        env_list=$(grep -v '^#' "${DOCKER_DIR}/${APP_ID}/.env" | grep -v '^$' | cut -d= -f1 | sed 's/^/  - /' || true)
    fi

    cat > "${target_dir}/ficha.md" <<EOF
---
id: "${APP_ID}"
name: "${APP}"
description: "Installed by DebMenux"
aliases:
  - ${APP_ID}
image: "${IMAGE}"
category: "${CATEGORY}"
port_default: ${port_main}
protocol: "http"
needs_proxy: false
needs_db: false
env_required:
${env_list}
backup_critical: true
backup_paths:
  - "./data"
protected: false
docs_url: ""
notes: "Auto-registered by DebMenux register_to_catalog()"
$(if [[ -n "$networks_yaml" ]]; then
echo "networks:"
echo "$networks_yaml"
fi)
---

# ${APP}

## Qué es

(Auto-registrado por DebMenux — completar manualmente)

## Configuración detectada

- Imagen: \`${IMAGE}\`
- Puerto: ${port_main}
- Categoría: ${CATEGORY}
- Instalado: $(date -u +"%Y-%m-%d")
$(if [[ ${#NETWORKS[@]:-0} -gt 0 ]]; then
echo "- Redes: ${NETWORKS[*]}"
fi)

## Notas

- Ficha generada automáticamente por DebMenux
- Editar para agregar documentación operativa
- Para guía completa: crear docs/services/${APP_ID}-guide.md
EOF
}

# Generate .env.example (replace secret values with __pega_aqui__)
_generate_env_example() {
    local target_dir="$1"
    local svc_dir="$2"

    if [[ ! -f "${svc_dir}/.env" ]]; then
        return 0
    fi

    # Copy .env but replace actual secret values with placeholder
    # Keep: TZ, non-secret config values
    # Replace: passwords, tokens, cookies
    local secret_patterns="PASSWORD|SECRET|TOKEN|COOKIE|KEY|PASS"

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]]; then
            echo "$line"
        elif [[ "$line" =~ ^([A-Z_]+)= ]]; then
            local key="${BASH_REMATCH[1]}"
            if [[ "$key" =~ ($secret_patterns) ]]; then
                echo "${key}=__pega_aqui__"
            else
                echo "$line"
            fi
        else
            echo "$line"
        fi
    done < "${svc_dir}/.env" > "${target_dir}/.env.example"
}

# ==============================================================================
# SECTION 4: CATALOG QUERY (used by nas-dotfiles agent)
# ==============================================================================

# Check if a service is registered in the catalog
is_registered() {
    local service_id="$1"
    [[ "$INTEGRATION_ENABLED" == "true" ]] && \
    [[ -f "${INTEGRATION_CATALOG_DIR}/${service_id}/ficha.md" ]]
}

# ==============================================================================
# SECTION 5: INITIALIZATION
# ==============================================================================

# Auto-load integration on source
load_integration_config
load_global_env
