#!/usr/bin/env bash
# ==========================================================
# DebMenux — Servicio: Home Assistant
# ==========================================================
# Fuente: https://www.home-assistant.io/
# GitHub: https://github.com/home-assistant/core
# Descripción: Plataforma de automatización del hogar
# Licencia: MIT
# ==========================================================

# ==============================================================================
# METADATOS DEL SERVICIO
# ==============================================================================

APP="Home Assistant"
APP_ID="homeassistant"
CATEGORY="iot"
IMAGE="ghcr.io/home-assistant/home-assistant:stable"
PORT_WEB="${PORT_WEB:-8123}"

# Recursos
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2G}"

# Redes (network_mode: host — no usa redes Docker)
NETWORKS=()

# ==============================================================================
# INSTALACIÓN
# ==============================================================================

install_service() {
    local svc_dir="${DOCKER_DIR}/${APP_ID}"

    # ── Paso 1: Crear directorios ─────────────────────────────
    msg_info "Creando directorios para ${APP}"
    mkdir -p "${svc_dir}/data/www/snapshots"
    mkdir -p "${svc_dir}/data/includes"
    msg_ok "Directorios creados 📁"

    # ── Paso 2: Generar .env ──────────────────────────────────
    msg_info "Generando .env"
    cat > "${svc_dir}/.env" <<EOF
# Home Assistant — Variables de entorno
# Generado por DebMenux el $(date -u +"%Y-%m-%d")
# Token para Homepage widget (crear en HA → Perfil → Long-Lived Access Tokens)
HOMEASSISTANT_TOKEN=__pega_aqui__
EOF
    secure_env "${svc_dir}/.env"
    msg_ok ".env creado 🔑"

    # ── Paso 3: Generar compose.yml ───────────────────────────
    msg_info "Generando compose.yml"
    local server_ip
    server_ip=$(get_server_ip)

    cat > "${svc_dir}/compose.yml" <<EOF
# Home Assistant — gestionado por DebMenux
services:
  homeassistant:
    image: ${IMAGE}
    container_name: ${APP_ID}
    restart: unless-stopped
    network_mode: host
    stop_grace_period: 60s
    dns:
      - 190.104.12.42
      - 200.73.96.146
      - 8.8.8.8
    privileged: true
    env_file:
      - ../.env
      - .env
    volumes:
      - ./data:/config
      - /etc/localtime:/etc/localtime:ro
      - /run/dbus:/run/dbus:ro
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8123"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    labels:
      - homepage.group=IoT
      - homepage.name=Home Assistant
      - homepage.icon=home-assistant
      - homepage.href=http://\${SERVER_IP}:${PORT_WEB}
      - homepage.description=Automatización del hogar
      - homepage.widget.type=homeassistant
      - homepage.widget.url=http://\${SERVER_IP}:${PORT_WEB}
      - homepage.widget.key=\${HOMEASSISTANT_TOKEN}
    deploy:
      resources:
        limits:
          cpus: '${var_cpu}'
          memory: ${var_ram}
        reservations:
          cpus: '0.5'
          memory: 512M
EOF
    msg_ok "compose.yml creado 📄"

    # ── Paso 4: Crear shell_commands.yaml (ntfy) ──────────────
    msg_info "Creando includes/shell_commands.yaml"
    cat > "${svc_dir}/data/includes/shell_commands.yaml" <<EOF
# Shell Commands — ntfy + utilidades
ntfy_camara: >
  curl -s -H "Title: 🚨 Movimiento detectado"
  -H "Priority: 4"
  -H "Tags: warning,camera"
  -H "Filename: alarma.jpg"
  -T /config/www/snapshots/alarma.jpg
  http://${server_ip}:8090/nas-alerts
EOF
    msg_ok "shell_commands.yaml creado ⚙️"

    # ── Paso 5: Iniciar servicio ──────────────────────────────
    msg_info "Iniciando ${APP}"
    docker compose -f "${svc_dir}/compose.yml" up -d
    msg_ok "${APP} iniciado 🟢"

    # ── Paso 6: Mostrar info de acceso ────────────────────────
    echo -e ""
    msg_success "${APP} instalado exitosamente! 🏠"
    echo -e "${TAB}${BOLD}🌐 Web UI:${CL}  ${BL}http://${server_ip}:${PORT_WEB}${CL}"
    echo -e ""
    echo -e "${TAB}${DIM}Primer acceso: crear usuario admin en el wizard.${CL}"
    echo -e "${TAB}${DIM}Homepage widget: crear Long-Lived Token en Perfil → pegarlo en .env${CL}"
    echo -e ""
    echo -e "${TAB}${BOLD}📋 Post-instalación:${CL}"
    echo -e "${TAB}  1. Completar wizard de onboarding"
    echo -e "${TAB}  2. Settings → Integrations → Add → ntfy (URL: http://${server_ip}:8090)"
    echo -e "${TAB}  3. Perfil → Long-Lived Token → copiar a \$dkco/${APP_ID}/.env"
    echo -e "${TAB}  4. svc recreate ${APP_ID} (para que Homepage tome el token)"
    echo -e ""
    echo -e "${TAB}${DIM}Guía completa: docs/services/homeassistant-guide.md${CL}"
    echo -e ""

    # ── Registrar en catálogo externo
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

    msg_info "Recreando contenedor (grace period 60s)"
    docker compose -f "${svc_dir}/compose.yml" up -d --force-recreate
    msg_ok "${APP} actualizado 🆙"
}
