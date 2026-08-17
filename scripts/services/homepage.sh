#!/usr/bin/env bash
# ==========================================================
# DebMenux — Servicio: Homepage
# ==========================================================
# Fuente: https://gethomepage.dev/
# GitHub: https://github.com/gethomepage/homepage
# Descripción: Dashboard de servicios del NAS con widgets.
#              Auto-descubre contenedores via Docker labels.
#              Configuración en YAML sin reiniciar.
# Licencia: MIT
# ==========================================================

# ==============================================================================
# METADATOS DEL SERVICIO
# ==============================================================================

APP="Homepage"
APP_ID="homepage"
CATEGORY="management"
IMAGE="ghcr.io/gethomepage/homepage:latest"
PORT_WEB="${PORT_WEB:-3000}"

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
    msg_ok "Directorios creados 📁"

    # ── Paso 2: Crear redes ───────────────────────────────────
    for net in "${NETWORKS[@]}"; do
        ensure_network "$net"
    done

    # ── Paso 3: Generar configuración base ────────────────────
    msg_info "Generando configuración base"
    local server_ip
    server_ip=$(get_server_ip)

    # settings.yaml
    cat > "${svc_dir}/config/settings.yaml" <<EOF
# Homepage settings
title: NAS Dashboard
background:
  image: ""
theme: dark
color: slate
headerStyle: clean
layout:
  IoT:
    style: row
    columns: 3
  Sistema:
    style: row
    columns: 3
  Bases de datos:
    style: row
    columns: 2
  Redes:
    style: row
    columns: 2
EOF

    # docker.yaml (para auto-descubrimiento de contenedores)
    cat > "${svc_dir}/config/docker.yaml" <<EOF
# Docker socket para auto-descubrimiento via labels
local:
  socket: /var/run/docker.sock
EOF

    # services.yaml (solo para servicios nativos / sin Docker)
    cat > "${svc_dir}/config/services.yaml" <<EOF
# Solo servicios NATIVOS (no Docker) van aquí
# Los servicios Docker se auto-descubren via labels en compose.yml
- Sistema:
    - USB Manager:
        icon: usb
        href: http://${server_ip}:8091
        description: Dispositivos USB conectados
        widget:
          type: customapi
          url: http://${server_ip}:8091/usb/list
          mappings:
            - field: count
              label: USBs montados
EOF

    # widgets.yaml
    cat > "${svc_dir}/config/widgets.yaml" <<EOF
# Widgets del header
- resources:
    cpu: true
    memory: true
    disk: /
- datetime:
    text_size: xl
    format:
      dateStyle: short
      timeStyle: short
      hour12: false
EOF

    # bookmarks.yaml (vacío por defecto)
    cat > "${svc_dir}/config/bookmarks.yaml" <<EOF
# Bookmarks (enlaces externos)
# - Desarrollo:
#     - GitHub:
#         - icon: github
#           href: https://github.com/ydiaz1699
EOF

    msg_ok "Configuración base creada ⚙️"

    # ── Paso 4: Generar compose.yml ───────────────────────────
    msg_info "Generando compose.yml"
    cat > "${svc_dir}/compose.yml" <<EOF
# Homepage — Dashboard de servicios (gestionado por DebMenux)
services:
  homepage:
    image: ${IMAGE}
    container_name: homepage
    restart: unless-stopped
    environment:
      TZ: \${TZ:-America/La_Paz}
      HOMEPAGE_ALLOWED_HOSTS: "*"
    ports:
      - "${PORT_WEB}:3000"
    volumes:
      - ./config:/app/config
      - /var/run/docker.sock:/var/run/docker.sock:ro
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
    healthcheck:
      test: ["CMD", "wget", "--no-verbose", "--tries=1", "--spider", "http://localhost:3000"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 15s

networks:
  homepage_net:
    external: true
EOF
    msg_ok "compose.yml creado 📄"

    # ── Paso 5: Iniciar servicio ──────────────────────────────
    msg_info "Iniciando ${APP}"
    docker compose -f "${svc_dir}/compose.yml" up -d
    msg_ok "${APP} iniciado 🟢"

    # ── Paso 6: Esperar y verificar ───────────────────────────
    sleep 5
    if curl -s --max-time 5 "http://localhost:${PORT_WEB}" >/dev/null 2>&1; then
        msg_ok "Dashboard accesible ✅"
    else
        msg_warn "Dashboard cargando — esperar unos segundos"
    fi

    # ── Paso 7: Mostrar info de acceso ────────────────────────
    echo -e ""
    msg_success "${APP} instalado exitosamente! 📊"
    echo -e "${TAB}${BOLD}🌐 Dashboard:${CL}   ${BL}http://${server_ip}:${PORT_WEB}${CL}"
    echo -e ""
    echo -e "${TAB}${DIM}• Los servicios Docker aparecen automáticamente via labels${CL}"
    echo -e "${TAB}${DIM}• Servicios nativos (usb-api): editar services.yaml${CL}"
    echo -e "${TAB}${DIM}• La config se aplica en caliente (no reiniciar)${CL}"
    echo -e "${TAB}${DIM}• Agregar labels a un servicio: svc recreate <servicio>${CL}"
    echo -e ""
    echo -e "${TAB}${BOLD}Labels para que un servicio aparezca:${CL}"
    echo -e "${TAB}${DIM}  - homepage.group=Grupo${CL}"
    echo -e "${TAB}${DIM}  - homepage.name=Nombre${CL}"
    echo -e "${TAB}${DIM}  - homepage.icon=icono${CL}"
    echo -e "${TAB}${DIM}  - homepage.href=http://\${SERVER_IP}:PUERTO${CL}"
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
