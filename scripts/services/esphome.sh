#!/usr/bin/env bash
# ==========================================================
# DebMenux — Servicio: ESPHome
# ==========================================================
# Fuente: https://esphome.io/
# GitHub: https://github.com/esphome/esphome
# Descripción: Dashboard para gestionar dispositivos ESP32/ESP8266.
#              Compilación, flash OTA/serial, y monitoreo desde web.
#              Usa network_mode: host para mDNS discovery.
# Licencia: MIT
# ==========================================================

# ==============================================================================
# METADATOS DEL SERVICIO
# ==============================================================================

APP="ESPHome"
APP_ID="esphome"
CATEGORY="iot"
IMAGE="ghcr.io/esphome/esphome:latest"
PORT_WEB="${PORT_WEB:-6052}"

# Recursos
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1G}"

# Redes (no aplica — usa network_mode: host)
NETWORKS=()

# ==============================================================================
# INSTALACIÓN
# ==============================================================================

install_service() {
    local svc_dir="${DOCKER_DIR}/${APP_ID}"

    # ── Paso 1: Crear directorios ─────────────────────────────
    msg_info "Creando directorios para ${APP}"
    mkdir -p "${svc_dir}/config"
    msg_ok "Directorios creados 📁"

    # ── Paso 2: Generar archivo .env ──────────────────────────
    msg_info "Generando .env"
    local server_ip
    server_ip=$(get_server_ip)

    cat > "${svc_dir}/.env" <<EOF
# ESPHome — Variables de entorno
# Generado por DebMenux el $(date -u +"%Y-%m-%d")
SERVER_IP=${server_ip}
EOF
    secure_env "${svc_dir}/.env"
    msg_ok ".env creado 🔑"

    # ── Paso 3: Generar compose.yml ───────────────────────────
    msg_info "Generando compose.yml"
    cat > "${svc_dir}/compose.yml" <<EOF
# ESPHome — Dashboard de dispositivos ESP (gestionado por DebMenux)
services:
  esphome:
    image: ${IMAGE}
    container_name: esphome
    restart: unless-stopped
    network_mode: host
    privileged: true
    env_file:
      - .env
    volumes:
      - ./config:/config:rw
      - /etc/localtime:/etc/localtime:ro
    devices:
      - /dev/ttyUSB0:/dev/ttyUSB0
    command: dashboard /config
    labels:
      - homepage.group=IoT
      - homepage.name=ESPHome
      - homepage.icon=esphome
      - homepage.href=http://\${SERVER_IP}:${PORT_WEB}
      - homepage.description=Gestión de dispositivos ESP32/ESP8266
      - homepage.widget.type=esphome
      - homepage.widget.url=http://\${SERVER_IP}:${PORT_WEB}
EOF
    msg_ok "compose.yml creado 📄"

    # ── Paso 4: Crear secrets.yaml template ───────────────────
    msg_info "Generando secrets.yaml template"
    cat > "${svc_dir}/config/secrets.yaml" <<EOF
# ESPHome secrets — NO commitear a git
# Completar con valores reales

wifi_ssid: "TU_RED_WIFI"
wifi_password: "TU_PASSWORD_WIFI"
mqtt_user: "esphome"
mqtt_password: "__pega_aqui__"
api_encryption_key: ""
ota_password: "$(generate_password)"
EOF
    chmod 600 "${svc_dir}/config/secrets.yaml"
    msg_ok "secrets.yaml template creado ⚙️"

    # ── Paso 5: Verificar acceso USB ──────────────────────────
    if [[ -e /dev/ttyUSB0 ]]; then
        msg_ok "Dispositivo USB detectado: /dev/ttyUSB0 ✅"
    else
        msg_warn "No se detectó /dev/ttyUSB0 — flash serial no disponible hasta conectar un ESP"
        msg_info "Flash OTA funcionará sin USB después del primer flash"
    fi

    # ── Paso 6: Iniciar servicio ──────────────────────────────
    msg_info "Iniciando ${APP}"
    docker compose -f "${svc_dir}/compose.yml" up -d
    msg_ok "${APP} iniciado 🟢"

    # ── Paso 7: Esperar y verificar ───────────────────────────
    sleep 5
    if curl -s --max-time 5 "http://localhost:${PORT_WEB}" >/dev/null 2>&1; then
        msg_ok "Dashboard accesible en puerto ${PORT_WEB} ✅"
    else
        msg_warn "Dashboard puede estar cargando — esperar unos segundos"
    fi

    # ── Paso 8: Mostrar info de acceso ────────────────────────
    local server_ip
    server_ip=$(get_server_ip)

    echo -e ""
    msg_success "${APP} instalado exitosamente! 🔌"
    echo -e "${TAB}${BOLD}🌐 Dashboard:${CL}   ${BL}http://${server_ip}:${PORT_WEB}${CL}"
    echo -e ""
    echo -e "${TAB}${DIM}• network_mode: host (necesario para mDNS/discovery)${CL}"
    echo -e "${TAB}${DIM}• privileged: true (necesario para USB serial)${CL}"
    echo -e "${TAB}${DIM}• Configuraciones YAML en: ${svc_dir}/config/${CL}"
    echo -e "${TAB}${DIM}• Editar secrets: nano ${svc_dir}/config/secrets.yaml${CL}"
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

    echo -e ""
    msg_info "Después de actualizar, recompilar dispositivos para usar nuevas features"
    echo -e ""
}
