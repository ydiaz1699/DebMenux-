#!/usr/bin/env bash
# ==========================================================
# DebMenux — Servicio: File Browser
# ==========================================================
# Fuente: https://filebrowser.org/
# GitHub: https://github.com/filebrowser/filebrowser
# Descripción: Explorador de archivos web para el NAS.
#              Permite navegar, subir, descargar y compartir
#              archivos desde cualquier dispositivo en la LAN.
#              Muestra USBs automontados en tiempo real (:rshared).
# Licencia: Apache 2.0
# ==========================================================

# ==============================================================================
# METADATOS DEL SERVICIO
# ==============================================================================

APP="File Browser"
APP_ID="filebrowser"
CATEGORY="storage"
IMAGE="filebrowser/filebrowser:latest"
PORT_WEB="${PORT_WEB:-8085}"

# Recursos
var_cpu="${var_cpu:-0.5}"
var_ram="${var_ram:-256M}"

# Redes (usa bridge default)
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

    # ── Paso 2: Verificar que /NAS existe ─────────────────────
    if [[ ! -d "/NAS" ]]; then
        msg_warn "/NAS no existe — creando..."
        mkdir -p /NAS/USB
        msg_ok "/NAS y /NAS/USB creados"
    fi

    # ── Paso 3: Generar archivo .env ──────────────────────────
    msg_info "Generando .env"
    local server_ip
    server_ip=$(get_server_ip)
    local fb_pass
    fb_pass=$(generate_password)

    cat > "${svc_dir}/.env" <<EOF
# File Browser — Variables de entorno
# Generado por DebMenux el $(date -u +"%Y-%m-%d")
SERVER_IP=${server_ip}

# Credenciales para el widget de Homepage
FILEBROWSER_USER=admin
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
    container_name: filebrowser
    restart: unless-stopped
    user: "0:0"
    env_file:
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
        reservations:
          cpus: '0.1'
          memory: 64M
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

    # ── Paso 6: Esperar y verificar ───────────────────────────
    sleep 4
    if curl -s --max-time 5 "http://localhost:${PORT_WEB}/health" >/dev/null 2>&1; then
        msg_ok "Servicio accesible ✅"
    else
        msg_warn "Puede estar cargando — esperar unos segundos"
    fi

    # ── Paso 7: Mostrar info de acceso ────────────────────────
    local server_ip
    server_ip=$(get_server_ip)

    echo -e ""
    msg_success "${APP} instalado exitosamente! 📂"
    echo -e "${TAB}${BOLD}🌐 Web UI:${CL}      ${BL}http://${server_ip}:${PORT_WEB}${CL}"
    echo -e "${TAB}${BOLD}👤 Usuario:${CL}     admin"
    echo -e "${TAB}${BOLD}🔑 Password:${CL}    admin (¡CAMBIAR en primer login!)"
    echo -e ""
    echo -e "${TAB}${DIM}• Corre como root (user 0:0) para acceso completo a /NAS${CL}"
    echo -e "${TAB}${DIM}• Mount :rshared — USBs aparecen automáticamente sin recrear${CL}"
    echo -e "${TAB}${DIM}• Archivos servidos desde: /NAS → /srv (dentro del contenedor)${CL}"
    echo -e "${TAB}${DIM}• Config/DB en: ${svc_dir}/config/${CL}"
    echo -e ""
    echo -e "${TAB}${YWB}⚠️  El password del widget Homepage es diferente al de la web UI${CL}"
    echo -e "${TAB}${YWB}   Widget: ver ${svc_dir}/.env | Web UI: admin/admin (cambiar!)${CL}"
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
}
