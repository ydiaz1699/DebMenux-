#!/usr/bin/env bash
# ==========================================================
# DebMenux — Servicio: EMQX
# ==========================================================
# Fuente: https://www.emqx.io/
# GitHub: https://github.com/emqx/emqx
# Descripción: Broker MQTT de alto rendimiento para IoT
# Licencia: MIT
# ==========================================================

# ==============================================================================
# METADATOS DEL SERVICIO
# ==============================================================================

APP="EMQX"
APP_ID="emqx"
CATEGORY="iot"
IMAGE="emqx/emqx:5.8.3"
PORT_MQTT="${PORT_MQTT:-1883}"
PORT_MQTTS="${PORT_MQTTS:-8883}"
PORT_WS="${PORT_WS:-8083}"
PORT_WSS="${PORT_WSS:-8084}"
PORT_DASHBOARD="${PORT_DASHBOARD:-18083}"

# Recursos
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1G}"

# Redes
NETWORKS=("iot_net")

# ==============================================================================
# INSTALACIÓN
# ==============================================================================

install_service() {
    local svc_dir="${DOCKER_DIR}/${APP_ID}"

    # ── Paso 1: Crear directorios ─────────────────────────────
    msg_info "Creando directorios"
    mkdir -p "${svc_dir}/data/data"
    mkdir -p "${svc_dir}/data/log"
    msg_ok "Directorios creados 📁"

    # ── Paso 2: Crear redes ───────────────────────────────────
    for net in "${NETWORKS[@]}"; do
        ensure_network "$net"
    done

    # ── Paso 3: Generar secretos ──────────────────────────────
    msg_info "Generando secretos"
    local node_cookie
    local dashboard_pass
    node_cookie=$(generate_token 32)
    dashboard_pass=$(generate_password 18)

    cat > "${svc_dir}/.env" <<EOF
# Variables de entorno de EMQX
# Generado por DebMenux el $(date -u +"%Y-%m-%d")
TZ=${TZ:-America/La_Paz}

# Cookie del nodo (token de autenticación de cluster)
EMQX_NODE_COOKIE=${node_cookie}

# Credenciales del dashboard
EMQX_DASHBOARD_USER=admin
EMQX_DASHBOARD_PASSWORD=${dashboard_pass}

# Seguridad
EMQX_ALLOW_ANONYMOUS=false

# Puertos (cambiar aquí para remapear)
EMQX_PORT_MQTT=${PORT_MQTT}
EMQX_PORT_MQTTS=${PORT_MQTTS}
EMQX_PORT_WS=${PORT_WS}
EMQX_PORT_WSS=${PORT_WSS}
EMQX_PORT_DASHBOARD=${PORT_DASHBOARD}
EOF
    secure_env "${svc_dir}/.env"
    msg_ok "Secretos generados 🔑"

    # ── Paso 4: Generar compose.yml ───────────────────────────
    msg_info "Generando compose.yml"
    cat > "${svc_dir}/compose.yml" <<'EOF'
# EMQX Broker MQTT — gestionado por DebMenux
services:
  emqx:
    image: emqx/emqx:5.8.3
    container_name: emqx
    restart: unless-stopped
    env_file: .env
    environment:
      EMQX_NODE__NAME: "emqx@emqx.iot_net"
      EMQX_NODE__COOKIE: "${EMQX_NODE_COOKIE}"
      EMQX_NODE__ROLE: core
      EMQX_CLUSTER__DISCOVERY_STRATEGY: manual
      EMQX_DASHBOARD__DEFAULT_USERNAME: "${EMQX_DASHBOARD_USER}"
      EMQX_DASHBOARD__DEFAULT_PASSWORD: "${EMQX_DASHBOARD_PASSWORD}"
      EMQX_ALLOW_ANONYMOUS: "${EMQX_ALLOW_ANONYMOUS:-false}"
      EMQX_LOG__CONSOLE_HANDLER__LEVEL: warning
    ports:
      - "${EMQX_PORT_MQTT:-1883}:1883"
      - "${EMQX_PORT_MQTTS:-8883}:8883"
      - "${EMQX_PORT_WS:-8083}:8083"
      - "${EMQX_PORT_WSS:-8084}:8084"
      - "${EMQX_PORT_DASHBOARD:-18083}:18083"
    volumes:
      - ./data/data:/opt/emqx/data
      - ./data/log:/opt/emqx/log
    networks:
      - iot_net
    ulimits:
      nofile:
        soft: 1048576
        hard: 1048576
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 1G
        reservations:
          cpus: '0.25'
          memory: 256M
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: ["CMD", "emqx", "ctl", "status"]
      interval: 15s
      timeout: 5s
      retries: 5
      start_period: 30s

networks:
  iot_net:
    external: true
EOF
    msg_ok "compose.yml creado 📄"

    # ── Paso 5: Iniciar servicio ──────────────────────────────
    msg_info "Iniciando ${APP}"
    docker compose -f "${svc_dir}/compose.yml" up -d
    msg_ok "${APP} iniciado 🟢"

    # ── Paso 6: Esperar a que esté listo ──────────────────────
    msg_info "Esperando a que ${APP} esté listo"
    local retries=0
    while [[ $retries -lt 15 ]]; do
        if docker exec emqx emqx ctl status 2>/dev/null | grep -q "is started"; then
            break
        fi
        sleep 2
        ((retries++))
    done

    if [[ $retries -ge 15 ]]; then
        msg_warn "${APP} sigue iniciando... revisa logs: docker logs emqx"
    else
        msg_ok "${APP} listo ✅"
    fi

    # ── Paso 7: Mostrar info de acceso ────────────────────────
    local server_ip
    server_ip=$(get_server_ip)

    echo -e ""
    msg_success "${APP} instalado exitosamente! 📡"
    echo -e "${TAB}${BOLD}🖥️  Dashboard:${CL}   ${BL}http://${server_ip}:${PORT_DASHBOARD}${CL}"
    echo -e "${TAB}${BOLD}📡 MQTT:${CL}        ${server_ip}:${PORT_MQTT}"
    echo -e "${TAB}${BOLD}🔒 MQTT/TLS:${CL}    ${server_ip}:${PORT_MQTTS}"
    echo -e "${TAB}${BOLD}🌐 WebSocket:${CL}   ${server_ip}:${PORT_WS}"
    echo -e "${TAB}${BOLD}🔐 WSS:${CL}         ${server_ip}:${PORT_WSS}"
    echo -e ""
    echo -e "${TAB}${BOLD}🔑 Login del Dashboard:${CL}"
    echo -e "${TAB}  Usuario: ${GN}admin${CL}"
    echo -e "${TAB}  Clave:   ${GN}${dashboard_pass}${CL}"
    echo -e ""
    echo -e "${TAB}${DIM}Credenciales guardadas en: ${svc_dir}/.env${CL}"
    echo -e "${TAB}${DIM}MQTT anónimo DESHABILITADO. Crea usuarios en el dashboard.${CL}"
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

    msg_warn "Nota: Upgrades de versión mayor pueden requerir migración de datos."
    msg_warn "Revisa: https://www.emqx.io/docs/en/latest/changes/breaking-changes.html"
}
