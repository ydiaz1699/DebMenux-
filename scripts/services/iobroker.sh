#!/usr/bin/env bash
# ==========================================================
# DebMenux — Servicio: ioBroker
# ==========================================================
# Fuente: https://hub.docker.com/r/buanet/iobroker
# GitHub: https://github.com/buanet/ioBroker.docker
# Descripción: Plataforma de automatización IoT y domótica.
# Licencia: MIT (script DebMenux)
# ==========================================================

APP="ioBroker"
APP_ID="iobroker"
CATEGORY="iot"
IMAGE="buanet/iobroker:v11.1.0"
PORT_WEB="${PORT_WEB:-8181}"

var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1G}"
NETWORKS=("iot_net")

install_service() {
    local svc_dir="${DOCKER_DIR}/${APP_ID}"

    # 1. Crear carpetas antes de crear archivos o aplicar permisos.
    msg_info "Creando directorios para ${APP}"
    mkdir -p "${svc_dir}/data"
    msg_ok "Directorios creados 📁"

    # 2. Crear la red externa si la instalación la necesita.
    for net in "${NETWORKS[@]}"; do
        ensure_network "$net"
    done

    # 3. Crear el .env local. ioBroker no requiere secretos en esta configuración.
    msg_info "Generando .env"
    cat > "${svc_dir}/.env" <<EOF
# ioBroker — no requiere variables locales inicialmente.
# SERVER_IP y TZ se heredan desde ../.env.
EOF

    # 4. Crear compose.yml. Si nas-dotfiles está instalado, heredar sus defaults.
    msg_info "Generando compose.yml"
    if [[ -f "${DOCKER_DIR}/_common.yml" ]]; then
        cat > "${svc_dir}/compose.yml" <<EOF
services:
  iobroker:
    extends:
      file: ../_common.yml
      service: _defaults
    image: ${IMAGE}
    container_name: iobroker
    hostname: iobroker
    env_file:
      - ../.env
      - .env
    environment:
      SETUID: "1000"
      SETGID: "1000"
      PERMISSION_CHECK: "true"
      IOB_ADMINPORT: "8081"
    volumes:
      - ./data:/opt/iobroker
    ports:
      - "${PORT_WEB}:8081"
    healthcheck:
      test: ["CMD", "/bin/bash", "-c", "/opt/scripts/healthcheck.sh"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    deploy:
      resources:
        limits:
          cpus: "${var_cpu}"
          memory: ${var_ram}
        reservations:
          cpus: "0.25"
          memory: 256M
    labels:
      - homepage.group=IoT
      - homepage.name=ioBroker
      - homepage.icon=iobroker
      - homepage.href=http://\${SERVER_IP}:${PORT_WEB}
      - homepage.description=Automatización IoT y domótica
    networks:
      - iot_net

networks:
  iot_net:
    external: true
EOF
    else
        cat > "${svc_dir}/compose.yml" <<EOF
services:
  iobroker:
    image: ${IMAGE}
    container_name: iobroker
    hostname: iobroker
    restart: unless-stopped
    env_file:
      - ../.env
      - .env
    environment:
      SETUID: "1000"
      SETGID: "1000"
      PERMISSION_CHECK: "true"
      IOB_ADMINPORT: "8081"
    volumes:
      - ./data:/opt/iobroker
    ports:
      - "${PORT_WEB}:8081"
    security_opt:
      - no-new-privileges:true
    # No cap_drop:[ALL]: adapters y dependencias se instalan en runtime.
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"
    healthcheck:
      test: ["CMD", "/bin/bash", "-c", "/opt/scripts/healthcheck.sh"]
      interval: 30s
      timeout: 10s
      retries: 5
      start_period: 60s
    deploy:
      resources:
        limits:
          cpus: "${var_cpu}"
          memory: ${var_ram}
        reservations:
          cpus: "0.25"
          memory: 256M
    labels:
      - homepage.group=IoT
      - homepage.name=ioBroker
      - homepage.icon=iobroker
      - homepage.href=http://\${SERVER_IP}:${PORT_WEB}
      - homepage.description=Automatización IoT y domótica
    networks:
      - iot_net

networks:
  iot_net:
    external: true
EOF
    fi
    msg_ok "compose.yml creado 📄"

    # 5. Aplicar permisos después de crear el archivo.
    secure_env "${svc_dir}/.env"
    msg_ok ".env protegido 🔑"

    # 6. Levantar y verificar mediante las utilidades de DebMenux.
    msg_info "Iniciando ${APP}"
    docker compose -f "${svc_dir}/compose.yml" up -d
    msg_ok "${APP} iniciado 🟢"

    echo -e ""
    msg_success "${APP} instalado exitosamente!"
    echo -e "${TAB}${BOLD}🌐 Panel:${CL} ${BL}http://$(get_server_ip):${PORT_WEB}${CL}"
    echo -e "${TAB}${DIM}• Persistencia: ${svc_dir}/data → /opt/iobroker${CL}"
    echo -e "${TAB}${DIM}• MQTT interno: emqx:1883 en iot_net${CL}"
    echo -e ""

    register_to_catalog
}

update_service() {
    local svc_dir="${DOCKER_DIR}/${APP_ID}"

    if [[ ! -f "${svc_dir}/compose.yml" ]]; then
        msg_error "No se encontró instalación de ${APP}."
        return 1
    fi

    msg_info "Descargando imagen fijada de ${APP}"
    docker compose -f "${svc_dir}/compose.yml" pull
    docker compose -f "${svc_dir}/compose.yml" up -d --force-recreate
    msg_ok "${APP} actualizado 🆙"
}
