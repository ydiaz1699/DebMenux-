#!/usr/bin/env bash
# ==========================================================
# DebMenux — Servicio: AdGuard Home
# ==========================================================
# Fuente: https://adguard.com/
# GitHub: https://github.com/AdguardTeam/AdGuardHome
# Descripción: Bloqueador de anuncios y rastreadores a nivel DNS
# Licencia: MIT
# ==========================================================

# ==============================================================================
# METADATOS DEL SERVICIO
# ==============================================================================

APP="AdGuard Home"
APP_ID="adguard"
CATEGORY="networking"
IMAGE="adguard/adguardhome:latest"
PORT_WEB="${PORT_WEB:-3000}"
PORT_DNS="${PORT_DNS:-53}"
PORT_ADMIN="${PORT_ADMIN:-8080}"

# Recursos
var_cpu="${var_cpu:-0.5}"
var_ram="${var_ram:-256M}"

# ==============================================================================
# INSTALACIÓN
# ==============================================================================

install_service() {
    local svc_dir="${DOCKER_DIR}/${APP_ID}"

    # Verificar si el puerto DNS está disponible
    if ss -tlnp | grep -q ":${PORT_DNS} " 2>/dev/null; then
        msg_warn "¡El puerto ${PORT_DNS} (DNS) ya está en uso!"
        msg_warn "Puede que necesites deshabilitar systemd-resolved primero:"
        echo -e "${TAB}  sudo systemctl disable --now systemd-resolved"
        echo -e "${TAB}  sudo rm /etc/resolv.conf"
        echo -e "${TAB}  echo 'nameserver 1.1.1.1' | sudo tee /etc/resolv.conf"
        echo -e ""
        if ! confirm "¿Continuar de todos modos?"; then
            msg_error "Instalación cancelada."
            return 1
        fi
    fi

    # ── Paso 1: Crear directorios ─────────────────────────────
    msg_info "Creando directorios"
    mkdir -p "${svc_dir}/data/work"
    mkdir -p "${svc_dir}/data/conf"
    msg_ok "Directorios creados 📁"

    # ── Paso 2: Generar compose.yml ───────────────────────────
    msg_info "Generando compose.yml"
    cat > "${svc_dir}/compose.yml" <<EOF
# AdGuard Home — gestionado por DebMenux
services:
  adguard:
    image: ${IMAGE}
    container_name: ${APP_ID}
    restart: unless-stopped
    ports:
      # DNS
      - "${PORT_DNS}:53/tcp"
      - "${PORT_DNS}:53/udp"
      # Asistente de configuración (solo primer arranque)
      - "${PORT_WEB}:3000/tcp"
      # Panel de administración (después de configurar)
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
    msg_ok "compose.yml creado 📄"

    # ── Paso 3: Iniciar servicio ──────────────────────────────
    msg_info "Iniciando ${APP}"
    docker compose -f "${svc_dir}/compose.yml" up -d
    msg_ok "${APP} iniciado 🟢"

    # ── Paso 4: Mostrar info de acceso ────────────────────────
    local server_ip
    server_ip=$(get_server_ip)

    echo -e ""
    msg_success "${APP} instalado exitosamente! 🛡️"
    echo -e "${TAB}${BOLD}🧙 Asistente:${CL}   ${BL}http://${server_ip}:${PORT_WEB}${CL}"
    echo -e "${TAB}${BOLD}🔧 Panel Admin:${CL} ${BL}http://${server_ip}:${PORT_ADMIN}${CL} (después de configurar)"
    echo -e "${TAB}${BOLD}🌐 DNS Server:${CL}  ${server_ip}:${PORT_DNS}"
    echo -e ""
    echo -e "${TAB}${DIM}Después de completar el asistente, el puerto ${PORT_WEB} ya no es necesario.${CL}"
    echo -e "${TAB}${DIM}Apunta el DNS de tus dispositivos/router a ${server_ip} para empezar a bloquear.${CL}"
    echo -e ""

    # ── Registrar en catálogo externo (si integración habilitada)
    register_to_catalog
}

# ==============================================================================
# ACTUALIZACIÓN
# ==============================================================================

update_service() {
    local svc_dir="${DOCKER_DIR}/${APP_ID}"

    if [[ ! -f "${svc_dir}/compose.yml" ]]; then
        msg_error "No se encontró instalación de ${APP}."
        return 1
    fi

    msg_info "Descargando última imagen"
    docker compose -f "${svc_dir}/compose.yml" pull
    msg_ok "Imagen actualizada 📥"

    msg_info "Recreando contenedor"
    docker compose -f "${svc_dir}/compose.yml" up -d --force-recreate
    msg_ok "${APP} actualizado 🆙"
}
