#!/usr/bin/env bash
# ==========================================================
# DebMenux — Servicio: Flowise
# ==========================================================
# Fuente: https://flowiseai.com/
# GitHub: https://github.com/FlowiseAI/Flowise
# Descripción: Constructor visual de agentes y flujos LLM.
# ==========================================================

APP="Flowise"
APP_ID="flowise"
CATEGORY="development"
IMAGE="flowiseai/flowise:latest"
PORT_WEB="${PORT_WEB:-8100}"

var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-1G}"
NETWORKS=("db_net")

_read_env_value() {
    local env_file="$1"
    local key="$2"
    [[ -f "$env_file" ]] || return 1
    grep -m1 "^${key}=" "$env_file" | cut -d= -f2-
}

_wait_for_postgres() {
    local retries=0
    while [[ $retries -lt 30 ]]; do
        if docker inspect -f '{{.State.Health.Status}}' datapostgres 2>/dev/null | grep -qx "healthy"; then
            return 0
        fi
        sleep 2
        ((retries++))
    done
    return 1
}

_provision_flowise_database() {
    local datasql_env="${DOCKER_DIR}/datasql/.env"
    local admin_user
    local admin_db
    local admin_password
    admin_user=$(_read_env_value "$datasql_env" POSTGRES_USER)
    admin_db=$(_read_env_value "$datasql_env" POSTGRES_DB)
    admin_password=$(_read_env_value "$datasql_env" POSTGRES_PASSWORD)

    if [[ -z "$admin_user" || -z "$admin_db" || -z "$admin_password" ]]; then
        msg_error "No se pudieron leer las credenciales de DataSQL desde ${datasql_env}."
        return 1
    fi

    msg_info "Esperando PostgreSQL de DataSQL"
    if ! _wait_for_postgres; then
        msg_error "datapostgres no está healthy. Ejecuta primero: svc health datasql"
        return 1
    fi

    local db_password
    db_password=$(_read_env_value "${DOCKER_DIR}/${APP_ID}/.env" FLOWISE_DB_PASSWORD)
    if [[ -z "$db_password" ]]; then
        msg_error "FLOWISE_DB_PASSWORD no está configurado."
        return 1
    fi

    msg_info "Creando usuario y base dedicada de Flowise"
    local role_sql
    role_sql=$(cat <<SQL
DO \$\$
BEGIN
    IF NOT EXISTS (SELECT FROM pg_catalog.pg_roles WHERE rolname = 'flowise_user') THEN
        CREATE ROLE flowise_user LOGIN PASSWORD '${db_password}';
    ELSE
        ALTER ROLE flowise_user WITH LOGIN PASSWORD '${db_password}';
    END IF;
END
\$\$;
SQL
)

    if ! docker exec -e "PGPASSWORD=${admin_password}" datapostgres \
        psql -U "$admin_user" -d "$admin_db" -v ON_ERROR_STOP=1 -c "$role_sql"; then
        msg_error "No se pudo crear/actualizar el usuario flowise_user."
        return 1
    fi

    local db_exists
    db_exists=$(docker exec -e "PGPASSWORD=${admin_password}" datapostgres \
        psql -U "$admin_user" -d "$admin_db" -Atqc \
        "SELECT 1 FROM pg_database WHERE datname = 'flowise_db';" 2>/dev/null | tr -d '[:space:]')

    if [[ "$db_exists" != "1" ]]; then
        docker exec -e "PGPASSWORD=${admin_password}" datapostgres \
            psql -U "$admin_user" -d "$admin_db" -v ON_ERROR_STOP=1 \
            -c 'CREATE DATABASE flowise_db OWNER flowise_user;' \
            || { msg_error "No se pudo crear flowise_db."; return 1; }
    fi

    msg_ok "Usuario flowise_user y base flowise_db listos ✅"
}

install_service() {
    local svc_dir="${DOCKER_DIR}/${APP_ID}"

    msg_info "Creando directorios para ${APP}"
    mkdir -p "${svc_dir}/data"
    msg_ok "Directorios creados 📁"

    msg_info "Generando secretos y .env"
    local db_password
    local secret_key
    db_password=$(openssl rand -hex 32)
    secret_key=$(openssl rand -hex 32)
    cat > "${svc_dir}/.env" <<EOF
# Flowise — generado por DebMenux el $(date -u +"%Y-%m-%d")
FLOWISE_DB_NAME=flowise_db
FLOWISE_DB_USER=flowise_user
FLOWISE_DB_PASSWORD=${db_password}
FLOWISE_SECRETKEY_OVERWRITE=${secret_key}
EOF
    secure_env "${svc_dir}/.env"
    msg_ok ".env creado con secretos 🔑"

    msg_info "Generando compose.yml"
    cat > "${svc_dir}/compose.yml" <<EOF
# Flowise — constructor visual de agentes y flujos LLM
services:
  flowise:
    extends:
      file: ../_common.yml
      service: _defaults
    image: ${IMAGE}
    container_name: flowise
    env_file:
      - ../.env
      - .env
    environment:
      PORT: "3000"
      DATABASE_TYPE: postgres
      DATABASE_PORT: "5432"
      DATABASE_HOST: datapostgres
      DATABASE_NAME: \${FLOWISE_DB_NAME}
      DATABASE_USER: \${FLOWISE_DB_USER}
      DATABASE_PASSWORD: \${FLOWISE_DB_PASSWORD}
      DATABASE_SSL: "false"
      SECRETKEY_PATH: /home/node/.flowise
      LOG_PATH: /home/node/.flowise/logs
      BLOB_STORAGE_PATH: /home/node/.flowise/storage
      LOG_LEVEL: info
      DISABLE_FLOWISE_TELEMETRY: "true"
      HTTP_SECURITY_CHECK: "true"
      PATH_TRAVERSAL_SAFETY: "true"
      CUSTOM_MCP_SECURITY_CHECK: "true"
      FLOWISE_SECRETKEY_OVERWRITE: \${FLOWISE_SECRETKEY_OVERWRITE}
    ports:
      - "${PORT_WEB}:3000"
    volumes:
      - ./data:/home/node/.flowise
    networks:
      - db_net
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3000/api/v1/ping"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    cap_drop: [ALL]
    labels:
      - homepage.group=IA y Automatización
      - homepage.name=Flowise
      - homepage.icon=flowise
      - homepage.href=http://\${SERVER_IP}:${PORT_WEB}
      - homepage.description=Constructor visual de agentes y flujos LLM
    deploy:
      resources:
        limits:
          cpus: '${var_cpu}'
          memory: ${var_ram}
        reservations:
          cpus: '0.25'
          memory: 256M
    entrypoint: /bin/sh -c "sleep 3; flowise start"

networks:
  db_net:
    external: true
EOF
    msg_ok "compose.yml creado 📄"

    msg_info "Aplicando permisos del volumen"
    chown -R 1000:1000 "${svc_dir}/data" 2>/dev/null || true

    for net in "${NETWORKS[@]}"; do
        ensure_network "$net"
    done

    _provision_flowise_database || return 1

    if [[ ! -f "${DOCKER_DIR}/_common.yml" ]]; then
        msg_error "Falta ${DOCKER_DIR}/_common.yml; no se puede validar el compose estándar."
        return 1
    fi

    msg_info "Iniciando ${APP}"
    docker compose -f "${svc_dir}/compose.yml" up -d
    msg_ok "${APP} iniciado 🟢"

    sleep 8
    local server_ip
    server_ip=$(get_server_ip)
    if curl -fsS --max-time 5 "http://127.0.0.1:${PORT_WEB}/api/v1/ping" >/dev/null 2>&1; then
        msg_ok "Flowise healthy ✅"
    else
        msg_warn "Flowise sigue iniciando; revisar: svc logs flowise"
    fi

    echo -e ""
    msg_success "${APP} instalado exitosamente!"
    echo -e "${TAB}${BOLD}🌐 Acceso:${CL} ${BL}http://${server_ip}:${PORT_WEB}${CL}"
    echo -e "${TAB}${DIM}PostgreSQL: flowise_db en datapostgres/db_net${CL}"
    echo -e "${TAB}${DIM}Datos: ${svc_dir}/data${CL}"
    echo -e ""

    register_to_catalog
}

update_service() {
    local svc_dir="${DOCKER_DIR}/${APP_ID}"
    if [[ ! -f "${svc_dir}/compose.yml" ]]; then
        msg_error "No se encontró instalación de ${APP}."
        return 1
    fi
    msg_info "Actualizando ${APP}"
    docker compose -f "${svc_dir}/compose.yml" pull
    docker compose -f "${svc_dir}/compose.yml" up -d --force-recreate
    msg_ok "${APP} actualizado 🆙"
}
