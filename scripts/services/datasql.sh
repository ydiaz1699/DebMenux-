#!/usr/bin/env bash
# ==========================================================
# DebMenux — Servicio: DataSQL
# ==========================================================
# Fuente: https://www.postgresql.org/ | https://www.pgadmin.org/ | https://redis.io/
# Descripción: Stack de bases de datos: PostgreSQL 16, pgAdmin 4
#              y Redis 7. Todos los servicios del NAS que necesiten
#              persistencia se conectan a este stack via db_net.
# Licencia: MIT
# ==========================================================

# ==============================================================================
# METADATOS DEL SERVICIO
# ==============================================================================

APP="DataSQL"
APP_ID="datasql"
CATEGORY="database"
IMAGE="postgres:16-alpine"
PORT_WEB="${PORT_WEB:-5050}"          # pgAdmin web UI

# Recursos (globales del stack)
var_cpu="${var_cpu:-2}"
var_ram="${var_ram:-2G}"

# Redes requeridas
NETWORKS=("db_net")

# ==============================================================================
# INSTALACIÓN
# ==============================================================================

install_service() {
    local svc_dir="${DOCKER_DIR}/${APP_ID}"

    # ── Paso 1: Crear directorios ─────────────────────────────
    msg_info "Creando directorios para ${APP}"
    mkdir -p "${svc_dir}/data/postgres/pgdata"
    mkdir -p "${svc_dir}/data/postgres/backups"
    mkdir -p "${svc_dir}/data/pgadmin"
    mkdir -p "${svc_dir}/data/redis"
    msg_ok "Directorios creados 📁"

    # ── Paso 2: Crear redes ───────────────────────────────────
    for net in "${NETWORKS[@]}"; do
        ensure_network "$net"
    done

    # ── Paso 3: Generar archivo .env ──────────────────────────
    msg_info "Generando .env"
    local pg_pass
    pg_pass=$(generate_password)
    local pgadmin_pass
    pgadmin_pass=$(generate_password)
    local redis_pass
    redis_pass=$(generate_password)

    cat > "${svc_dir}/.env" <<EOF
# DataSQL — Variables de entorno
# Generado por DebMenux el $(date -u +"%Y-%m-%d")

# === PostgreSQL ===
POSTGRES_DB=homelab
POSTGRES_USER=nasadmin
POSTGRES_PASSWORD=${pg_pass}

# === pgAdmin ===
PGADMIN_EMAIL=admin@local.lan
PGADMIN_PASSWORD=${pgadmin_pass}

# === Redis ===
REDIS_PASSWORD=${redis_pass}
EOF
    secure_env "${svc_dir}/.env"
    msg_ok ".env creado con secretos generados 🔑"

    # ── Paso 4: Generar compose.yml ───────────────────────────
    msg_info "Generando compose.yml"
    local server_ip
    server_ip=$(get_server_ip)

    cat > "${svc_dir}/compose.yml" <<EOF
# DataSQL — Stack de bases de datos (gestionado por DebMenux)
services:
  postgres:
    image: postgres:16-alpine
    container_name: datapostgres
    restart: unless-stopped
    env_file:
      - ../.env
      - .env
    environment:
      POSTGRES_DB: \${POSTGRES_DB}
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      PGDATA: /var/lib/postgresql/data/pgdata
      POSTGRES_INITDB_ARGS: "--auth-host=scram-sha-256 --auth-local=scram-sha-256"
    volumes:
      - ./data/postgres/pgdata:/var/lib/postgresql/data/pgdata
      - ./data/postgres/backups:/backups
    networks:
      - db_net
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 30s
    security_opt:
      - no-new-privileges:true
    cap_drop: [ALL]
    cap_add: [CHOWN, DAC_OVERRIDE, SETUID, SETGID]
    deploy:
      resources:
        limits:
          cpus: '2'
          memory: 2G
        reservations:
          cpus: '0.5'
          memory: 512M

  pgadmin:
    image: dpage/pgadmin4:latest
    container_name: datapgadmin
    restart: unless-stopped
    env_file:
      - ../.env
      - .env
    environment:
      PGADMIN_DEFAULT_EMAIL: \${PGADMIN_EMAIL}
      PGADMIN_DEFAULT_PASSWORD: \${PGADMIN_PASSWORD}
      PGADMIN_CONFIG_SERVER_MODE: "True"
      PGADMIN_CONFIG_MASTER_PASSWORD_REQUIRED: "False"
    volumes:
      - ./data/pgadmin:/var/lib/pgadmin
    ports:
      - "${PORT_WEB}:80"
    depends_on:
      postgres:
        condition: service_healthy
    networks:
      - db_net
    labels:
      - homepage.group=Bases de datos
      - homepage.name=pgAdmin
      - homepage.icon=pgadmin
      - homepage.href=http://\${SERVER_IP}:${PORT_WEB}
      - homepage.description=Administración de PostgreSQL (datasql)
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 512M
        reservations:
          cpus: '0.25'
          memory: 128M

  redis:
    image: redis:7-alpine
    container_name: dataredis
    restart: unless-stopped
    command:
      - redis-server
      - --appendonly
      - "yes"
      - --requirepass
      - "\${REDIS_PASSWORD}"
    volumes:
      - ./data/redis:/data
    networks:
      - db_net
    healthcheck:
      test: ["CMD", "redis-cli", "-a", "\${REDIS_PASSWORD}", "ping"]
      interval: 10s
      timeout: 5s
      retries: 5
      start_period: 10s
    security_opt:
      - no-new-privileges:true
    cap_drop: [ALL]
    cap_add: [CHOWN, DAC_OVERRIDE, SETUID, SETGID]
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M
        reservations:
          cpus: '0.1'
          memory: 64M

networks:
  db_net:
    external: true
EOF
    msg_ok "compose.yml creado 📄"

    # ── Paso 5: Permisos ──────────────────────────────────────
    # pgadmin requiere uid 5050 para su directorio de datos
    chown -R 5050:5050 "${svc_dir}/data/pgadmin" 2>/dev/null || true

    # ── Paso 6: Iniciar servicio ──────────────────────────────
    msg_info "Iniciando ${APP} (PostgreSQL + pgAdmin + Redis)"
    docker compose -f "${svc_dir}/compose.yml" up -d
    msg_ok "${APP} iniciado 🟢"

    # ── Paso 7: Esperar a que PostgreSQL esté healthy ─────────
    msg_info "Esperando a que PostgreSQL esté listo..."
    local retries=0
    while [[ $retries -lt 30 ]]; do
        if docker exec datapostgres pg_isready -U nasadmin -d homelab >/dev/null 2>&1; then
            msg_ok "PostgreSQL listo ✅"
            break
        fi
        sleep 2
        ((retries++))
    done

    # ── Paso 8: Mostrar info de acceso ────────────────────────
    echo -e ""
    msg_success "${APP} instalado exitosamente! 🗄️"
    echo -e "${TAB}${BOLD}🌐 pgAdmin:${CL}     ${BL}http://${server_ip}:${PORT_WEB}${CL}"
    echo -e "${TAB}${BOLD}📧 Email:${CL}       admin@local.lan"
    echo -e "${TAB}${BOLD}🔑 Password:${CL}    (ver ${svc_dir}/.env)"
    echo -e ""
    echo -e "${TAB}${DIM}PostgreSQL: interno (solo via db_net, no expuesto al host)${CL}"
    echo -e "${TAB}${DIM}Redis: interno (solo via db_net, no expuesto al host)${CL}"
    echo -e "${TAB}${DIM}Otros servicios se conectan via red 'db_net'${CL}"
    echo -e ""
    echo -e "${TAB}${YWB}⚠️  Anotar los passwords generados: nano ${svc_dir}/.env${CL}"
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

    msg_info "Descargando últimas imágenes (postgres, pgadmin, redis)"
    docker compose -f "${svc_dir}/compose.yml" pull
    msg_ok "Imágenes actualizadas 📥"

    msg_info "Recreando contenedores"
    docker compose -f "${svc_dir}/compose.yml" up -d --force-recreate
    msg_ok "${APP} actualizado 🆙"

    # Verificar que PostgreSQL sigue healthy
    sleep 5
    if docker exec datapostgres pg_isready -U nasadmin >/dev/null 2>&1; then
        msg_ok "PostgreSQL healthy después del update ✅"
    else
        msg_warn "PostgreSQL puede estar arrancando — verificar con: svc health datasql"
    fi
}
