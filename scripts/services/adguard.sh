#!/usr/bin/env bash
# ==========================================================
# DebMenux - Service: AdGuard Home
# ==========================================================
# Source: https://adguard.com/
# GitHub: https://github.com/AdguardTeam/AdGuardHome
# Description: Network-wide ad/tracker blocker with DNS
# License: MIT
# ==========================================================

# ==============================================================================
# SERVICE METADATA
# ==============================================================================

APP="AdGuard Home"
APP_ID="adguard"
CATEGORY="networking"
IMAGE="adguard/adguardhome:latest"
PORT_WEB="${PORT_WEB:-3000}"
PORT_DNS="${PORT_DNS:-53}"
PORT_ADMIN="${PORT_ADMIN:-8080}"

# Resources
var_cpu="${var_cpu:-0.5}"
var_ram="${var_ram:-256M}"

# ==============================================================================
# INSTALL
# ==============================================================================

install_service() {
    local svc_dir="${DOCKER_DIR}/${APP_ID}"

    # Check if DNS port is available
    if ss -tlnp | grep -q ":${PORT_DNS} " 2>/dev/null; then
        msg_warn "Port ${PORT_DNS} (DNS) is already in use!"
        msg_warn "You may need to disable systemd-resolved first:"
        echo -e "${TAB}  sudo systemctl disable --now systemd-resolved"
        echo -e "${TAB}  sudo rm /etc/resolv.conf"
        echo -e "${TAB}  echo 'nameserver 1.1.1.1' | sudo tee /etc/resolv.conf"
        echo -e ""
        if ! confirm "Continue anyway?"; then
            msg_error "Installation cancelled."
            return 1
        fi
    fi

    # ── Step 1: Create directories ────────────────────────────
    msg_info "Creating directories"
    mkdir -p "${svc_dir}/data/work"
    mkdir -p "${svc_dir}/data/conf"
    msg_ok "Directories created"

    # ── Step 2: Generate compose.yml ──────────────────────────
    msg_info "Generating compose.yml"
    cat > "${svc_dir}/compose.yml" <<EOF
# AdGuard Home — managed by DebMenux
services:
  adguard:
    image: ${IMAGE}
    container_name: ${APP_ID}
    restart: unless-stopped
    ports:
      # DNS
      - "${PORT_DNS}:53/tcp"
      - "${PORT_DNS}:53/udp"
      # Setup wizard (first run only)
      - "${PORT_WEB}:3000/tcp"
      # Admin panel (after setup)
      - "${PORT_ADMIN}:80/tcp"
    volumes:
      - ./data/work:/opt/adguardhome/work
      - ./data/conf:/opt/adguardhome/conf
    deploy:
      resources:
        limits:
          cpus: '${var_cpu}'
          memory: ${var_ram}
        reservations:
          cpus: '0.1'
          memory: 64M
    security_opt:
      - no-new-privileges:true
    cap_drop: [ALL]
    cap_add:
      - NET_BIND_SERVICE
      - CHOWN
      - DAC_OVERRIDE
      - SETUID
      - SETGID
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:80"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
EOF
    msg_ok "compose.yml created"

    # ── Step 3: Start service ─────────────────────────────────
    msg_info "Starting ${APP}"
    docker compose -f "${svc_dir}/compose.yml" up -d
    msg_ok "${APP} started"

    # ── Step 4: Show access info ──────────────────────────────
    local server_ip
    server_ip=$(get_server_ip)

    echo -e ""
    msg_success "${APP} installed successfully!"
    echo -e "${TAB}${BOLD}Setup Wizard:${CL}  ${BL}http://${server_ip}:${PORT_WEB}${CL}"
    echo -e "${TAB}${BOLD}Admin Panel:${CL}   ${BL}http://${server_ip}:${PORT_ADMIN}${CL} (after setup)"
    echo -e "${TAB}${BOLD}DNS Server:${CL}    ${server_ip}:${PORT_DNS}"
    echo -e ""
    echo -e "${TAB}${DIM}After completing the setup wizard, port ${PORT_WEB} is no longer needed.${CL}"
    echo -e "${TAB}${DIM}Point your devices/router DNS to ${server_ip} to start blocking.${CL}"
    echo -e ""

    # ── Register to external catalog (if integration enabled) ─
    register_to_catalog
}

# ==============================================================================
# UPDATE
# ==============================================================================

update_service() {
    local svc_dir="${DOCKER_DIR}/${APP_ID}"

    if [[ ! -f "${svc_dir}/compose.yml" ]]; then
        msg_error "No ${APP} installation found!"
        return 1
    fi

    msg_info "Pulling latest image"
    docker compose -f "${svc_dir}/compose.yml" pull
    msg_ok "Image updated"

    msg_info "Recreating container"
    docker compose -f "${svc_dir}/compose.yml" up -d --force-recreate
    msg_ok "${APP} updated successfully"
}
