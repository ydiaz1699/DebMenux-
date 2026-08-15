#!/usr/bin/env bash
# ==========================================================
# DebMenux — Servicio: ntfy
# ==========================================================
# Fuente: https://ntfy.sh/
# GitHub: https://github.com/binwiederhier/ntfy
# Descripción: Servidor de notificaciones push HTTP pub-sub
#              self-hosted. Envía notificaciones a Android (app)
#              y Windows/Linux (browser PWA) sin internet.
# Licencia: MIT
# ==========================================================

# ==============================================================================
# METADATOS DEL SERVICIO
# ==============================================================================

APP="ntfy"
APP_ID="ntfy"
CATEGORY="monitoring"
IMAGE="binwiederhier/ntfy:latest"
PORT_WEB="${PORT_WEB:-8090}"

# Recursos
var_cpu="${var_cpu:-0.5}"
var_ram="${var_ram:-256M}"

# Redes
NETWORKS=("homepage_net")

# ==============================================================================
# INSTALACIÓN
# ==============================================================================

install_service() {
    local svc_dir="${DOCKER_DIR}/${APP_ID}"

    # ── Paso 1: Crear directorios ─────────────────────────────
    msg_info "Creando directorios para ${APP}"
    mkdir -p "${svc_dir}/config"
    mkdir -p "${svc_dir}/data/cache"
    mkdir -p "${svc_dir}/data/lib"
    mkdir -p "${svc_dir}/data/attachments"
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
# ntfy — Variables de entorno
# Generado por DebMenux el $(date -u +"%Y-%m-%d")
TZ=${TZ:-America/La_Paz}
SERVER_IP=${server_ip}
EOF
    secure_env "${svc_dir}/.env"
    msg_ok ".env creado 🔑"

    # ── Paso 4: Generar configuración server.yml ──────────────
    msg_info "Generando config/server.yml"
    cat > "${svc_dir}/config/server.yml" <<EOF
# ntfy server configuration
# Docs: https://docs.ntfy.sh/config/

# Base URL (para links en notificaciones)
base-url: "http://${server_ip}:${PORT_WEB}"

# Escuchar en todas las interfaces dentro del contenedor
listen-http: ":80"

# Cache (mensajes se almacenan aquí temporalmente)
cache-file: "/var/cache/ntfy/cache.db"
cache-duration: "24h"

# Attachments (imágenes de cámaras, archivos adjuntos)
attachment-cache-dir: "/var/cache/ntfy/attachments"
attachment-total-size-limit: "1G"
attachment-file-size-limit: "10M"
attachment-expiry-duration: "24h"

# Auth: read-write abierto en LAN (sin auth por defecto)
# Cambiar a "deny-all" y crear usuarios si se expone a internet
auth-default-access: "read-write"

# No estamos detrás de un proxy (directo LAN)
behind-proxy: false

# Keepalive para conexiones WebSocket
keepalive-interval: "45s"

# Limites para evitar abuso
visitor-subscription-limit: 30
visitor-request-limit-burst: 60
visitor-request-limit-replenish: "5s"
visitor-attachment-total-size-limit: "100M"
EOF
    msg_ok "server.yml creado ⚙️"

    # ── Paso 5: Generar compose.yml ───────────────────────────
    msg_info "Generando compose.yml"
    cat > "${svc_dir}/compose.yml" <<EOF
# ntfy — Servidor de notificaciones push (gestionado por DebMenux)
services:
  ntfy:
    image: ${IMAGE}
    container_name: ${APP_ID}
    restart: unless-stopped
    command: serve
    env_file:
      - .env
    ports:
      - "${PORT_WEB}:80"
    volumes:
      - ./config:/etc/ntfy
      - ./data/cache:/var/cache/ntfy
      - ./data/lib:/var/lib/ntfy
      - ./data/attachments:/var/cache/ntfy/attachments
    networks:
      - homepage_net
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
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:80/v1/health"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 10s
    labels:
      - homepage.group=Sistema
      - homepage.name=ntfy
      - homepage.icon=ntfy
      - homepage.href=http://\${SERVER_IP}:${PORT_WEB}
      - homepage.description=Notificaciones push del NAS

networks:
  homepage_net:
    external: true
EOF
    msg_ok "compose.yml creado 📄"

    # ── Paso 6: Permisos ──────────────────────────────────────
    chmod 644 "${svc_dir}/config/server.yml"

    # ── Paso 7: Iniciar servicio ──────────────────────────────
    msg_info "Iniciando ${APP}"
    docker compose -f "${svc_dir}/compose.yml" up -d
    msg_ok "${APP} iniciado 🟢"

    # ── Paso 8: Configurar NTFY_URL global para el sistema ────
    msg_info "Configurando NTFY_URL global"
    local ntfy_env_line="NTFY_URL=http://${server_ip}:${PORT_WEB}"
    if ! grep -q "^NTFY_URL=" /etc/environment 2>/dev/null; then
        echo "$ntfy_env_line" >> /etc/environment
        msg_ok "NTFY_URL configurada en /etc/environment"
    else
        sed -i "s|^NTFY_URL=.*|${ntfy_env_line}|" /etc/environment
        msg_ok "NTFY_URL actualizada en /etc/environment"
    fi
    export NTFY_URL="http://${server_ip}:${PORT_WEB}"

    # ── Paso 9: Enviar notificación de prueba ─────────────────
    sleep 3  # Esperar a que ntfy arranque
    msg_info "Enviando notificación de prueba"
    if curl -s --max-time 5 \
        -H "Title: 🎉 ntfy instalado" \
        -H "Tags: tada,white_check_mark" \
        -d "Servidor ntfy funcionando en ${server_ip}:${PORT_WEB}. Suscríbete al topic 'nas-alerts' desde tu celular o PC." \
        "http://localhost:${PORT_WEB}/nas-alerts" >/dev/null 2>&1; then
        msg_ok "Notificación de prueba enviada ✅"
    else
        msg_warn "No se pudo enviar la notificación de prueba (ntfy puede estar arrancando)"
    fi

    # ── Paso 10: Mostrar info de acceso ───────────────────────
    echo -e ""
    msg_success "${APP} instalado exitosamente! 🔔"
    echo -e "${TAB}${BOLD}🌐 Web UI:${CL}      ${BL}http://${server_ip}:${PORT_WEB}${CL}"
    echo -e "${TAB}${BOLD}📱 Android:${CL}     Instala la app 'ntfy' → Agregar servidor → http://${server_ip}:${PORT_WEB}"
    echo -e "${TAB}${BOLD}🖥️  Windows:${CL}    Abre la URL en Chrome → Permitir notificaciones → Instalar como PWA"
    echo -e ""
    echo -e "${TAB}${DIM}Topics configurados: usb, docker, backups, system, alarma, nas-alerts${CL}"
    echo -e "${TAB}${DIM}Probar: curl -d \"Hola mundo\" http://${server_ip}:${PORT_WEB}/nas-alerts${CL}"
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
