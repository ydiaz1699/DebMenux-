#!/usr/bin/env bash
# ==========================================================
# DebMenux — Servicio: Node-RED
# ==========================================================
# Fuente: https://nodered.org/
# GitHub: https://github.com/node-red/node-red
# Descripción: Plataforma visual de automatización de flujos IoT.
#              Conecta EMQX (MQTT), APIs, Home Assistant, y más
#              con flujos drag-and-drop.
# Licencia: Apache 2.0
# ==========================================================

# ==============================================================================
# METADATOS DEL SERVICIO
# ==============================================================================

APP="Node-RED"
APP_ID="node-red"
CATEGORY="iot"
IMAGE="nodered/node-red:latest"
PORT_WEB="${PORT_WEB:-1880}"

# Recursos
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512M}"

# Redes
NETWORKS=("iot_net")

# ==============================================================================
# INSTALACIÓN
# ==============================================================================

install_service() {
    local svc_dir="${DOCKER_DIR}/${APP_ID}"

    # ── Paso 1: Crear directorios ─────────────────────────────
    msg_info "Creando directorios para ${APP}"
    mkdir -p "${svc_dir}/data"
    msg_ok "Directorios creados 📁"

    # ── Paso 2: Crear redes ───────────────────────────────────
    for net in "${NETWORKS[@]}"; do
        ensure_network "$net"
    done

    # ── Paso 3: Generar archivo .env ──────────────────────────
    msg_info "Generando .env"
    local server_ip
    server_ip=$(get_server_ip)

    cat > "${svc_dir}/.env" <<EOF
# Node-RED — Variables de entorno
# Generado por DebMenux el $(date -u +"%Y-%m-%d")
SERVER_IP=${server_ip}
TZ=${TZ:-America/La_Paz}
EOF
    secure_env "${svc_dir}/.env"
    msg_ok ".env creado 🔑"

    # ── Paso 4: Generar compose.yml ───────────────────────────
    msg_info "Generando compose.yml"
    cat > "${svc_dir}/compose.yml" <<EOF
# Node-RED — Flujos de automatización IoT (gestionado por DebMenux)
services:
  node-red:
    image: ${IMAGE}
    container_name: node-red
    restart: unless-stopped
    env_file:
      - ../.env
      - .env
    ports:
      - "${PORT_WEB}:1880"
    volumes:
      - ./data:/data
    networks:
      - iot_net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:1880"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 20s
    labels:
      - homepage.group=IoT
      - homepage.name=Node-RED
      - homepage.icon=node-red
      - homepage.href=http://\${SERVER_IP}:${PORT_WEB}
      - homepage.description=Flujos de automatización IoT

networks:
  iot_net:
    external: true
EOF
    msg_ok "compose.yml creado 📄"

    # ── Paso 5: Permisos ──────────────────────────────────────
    # Node-RED corre como uid 1000 dentro del contenedor
    chown -R 1000:1000 "${svc_dir}/data" 2>/dev/null || true

    # ── Paso 6: Iniciar servicio ──────────────────────────────
    msg_info "Iniciando ${APP}"
    docker compose -f "${svc_dir}/compose.yml" up -d
    msg_ok "${APP} iniciado 🟢"

    # ── Paso 7: Esperar y verificar ───────────────────────────
    sleep 8  # Node-RED tarda un poco en arrancar
    if curl -s --max-time 5 "http://localhost:${PORT_WEB}" >/dev/null 2>&1; then
        msg_ok "Editor accesible ✅"
    else
        msg_warn "Node-RED puede estar cargando — esperar 10-15 segundos"
    fi

    # ── Paso 8: Mostrar info de acceso ────────────────────────
    local server_ip
    server_ip=$(get_server_ip)

    echo -e ""
    msg_success "${APP} instalado exitosamente! 🔴"
    echo -e "${TAB}${BOLD}🌐 Editor:${CL}      ${BL}http://${server_ip}:${PORT_WEB}${CL}"
    echo -e ""
    echo -e "${TAB}${DIM}• Conectado a iot_net (acceso a EMQX via hostname 'emqx')${CL}"
    echo -e "${TAB}${DIM}• Flujos se guardan en: ${svc_dir}/data/flows.json${CL}"
    echo -e "${TAB}${DIM}• NO usar cap_drop (Node-RED instala npm packages en runtime)${CL}"
    echo -e ""
    echo -e "${TAB}${BOLD}Conexión MQTT (en Node-RED):${CL}"
    echo -e "${TAB}${DIM}  Server: emqx  |  Port: 1883  |  User: nodered${CL}"
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

    msg_info "Recreando contenedor"
    docker compose -f "${svc_dir}/compose.yml" up -d --force-recreate
    msg_ok "${APP} actualizado 🆙"

    msg_warn "Los paquetes npm instalados se preservan (están en ./data/node_modules)"
}
