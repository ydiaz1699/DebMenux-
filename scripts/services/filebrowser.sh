#!/usr/bin/env bash
# ==========================================================
# DebMenux — Servicio: File Browser
# ==========================================================
# Fuente: https://filebrowser.org/
# GitHub: https://github.com/filebrowser/filebrowser
# Descripción: Explorador de archivos web para el NAS.
#              Permite navegar, subir, descargar y gestionar
#              archivos desde el navegador. Monta /NAS con
#              :rshared para ver USBs hot-plug automáticamente.
# Licencia: Apache-2.0
# ==========================================================

# ==============================================================================
# METADATOS DEL SERVICIO
# ==============================================================================

APP="File Browser"
APP_ID="filebrowser"
CATEGORY="archivos"
IMAGE="filebrowser/filebrowser:latest"
PORT_WEB="${PORT_WEB:-8085}"

# Recursos
var_cpu="${var_cpu:-0.5}"
var_ram="${var_ram:-256M}"

# Redes — no necesita red personalizada (bridge default)
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

    # ── Paso 2: Verificar mount base /NAS ─────────────────────
    if [[ ! -d "/NAS" ]]; then
        msg_warn "/NAS no existe — creando"
        mkdir -p /NAS
    fi

    # ── Paso 3: Generar archivo .env ──────────────────────────
    msg_info "Generando .env"
    local server_ip
    server_ip=$(get_server_ip)
    local fb_user="admin"
    local fb_pass
    fb_pass=$(generate_password)

    cat > "${svc_dir}/.env" <<EOF
# File Browser — Variables de entorno
# Generado por DebMenux el $(date -u +"%Y-%m-%d")

# Credenciales para widget de Homepage
FILEBROWSER_USER=${fb_user}
FILEBROWSER_PASSWORD=${fb_pass}
EOF
    secure_env "${svc_dir}/.env"
    msg_ok ".env creado 🔑"

    # ── Paso 4: Generar compose.yml ───────────────────────────
    msg_info "Generando compose.yml"
    cat > "${svc_dir}/compose.yml" <<EOF
# File Browser — Explorador de archivos web (gestionado por DebMenux)
services:
  filebrowser:
    image: ${IMAGE}
    container_name: ${APP_ID}
    restart: unless-stopped
    user: "0:0"
    env_file:
      - ../.env
      - .env
    ports:
      - "${PORT_WEB}:80"
    volumes:
      - ./config:/config
      - /NAS:/srv:rshared
    command: >
      --database /config/database.db
      --root /srv
      --address 0.0.0.0
      --port 80
      --log stdout
    deploy:
      resources:
        limits:
          cpus: '${var_cpu}'
          memory: ${var_ram}
    security_opt:
      - no-new-privileges:true
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:80/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    labels:
      - homepage.group=Archivos
      - homepage.name=Filebrowser
      - homepage.icon=filebrowser
      - homepage.href=http://\${SERVER_IP}:${PORT_WEB}
      - homepage.description=Explorador de archivos del NAS
      - homepage.widget.type=filebrowser
      - homepage.widget.url=http://\${SERVER_IP}:${PORT_WEB}
      - homepage.widget.username=\${FILEBROWSER_USER}
      - homepage.widget.password=\${FILEBROWSER_PASSWORD}
EOF
    msg_ok "compose.yml creado 📄"

    # ── Paso 5: Iniciar servicio ──────────────────────────────
    msg_info "Iniciando ${APP}"
    docker compose -f "${svc_dir}/compose.yml" up -d
    msg_ok "${APP} iniciado 🟢"

    # ── Paso 6: Esperar a que arranque y mostrar info ─────────
    sleep 3
    local server_ip
    server_ip=$(get_server_ip)

    echo -e ""
    msg_success "${APP} instalado exitosamente! 📂"
    echo -e "${TAB}${BOLD}🌐 Acceso:${CL}       ${BL}http://${server_ip}:${PORT_WEB}${CL}"
    echo -e "${TAB}${BOLD}👤 Usuario:${CL}      admin"
    echo -e "${TAB}${BOLD}🔑 Contraseña:${CL}   admin  ${DIM}(cambiar inmediatamente en Settings)${CL}"
    echo -e ""
    echo -e "${TAB}${DIM}Nota: El login inicial es admin/admin.${CL}"
    echo -e "${TAB}${DIM}El .env guarda las credenciales para el widget de Homepage.${CL}"
    echo -e "${TAB}${DIM}Los USBs montados en /NAS/USB/ aparecen automáticamente (:rshared).${CL}"
    echo -e ""

    # ── Paso 7: Registrar en catálogo externo
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
