#!/usr/bin/env bash
# ==========================================================
# DebMenux — Script de Instalación de Servicio (Plantilla)
# ==========================================================
# Archivo: scripts/services/_template.sh
# Descripción: Copia esta plantilla para crear un nuevo script
#              de instalación de servicio. Reemplaza <PLACEHOLDERS>.
#
# Nomenclatura: scripts/services/<service_id>.sh
#               El nombre del archivo (sin .sh) debe coincidir
#               con el campo "id" en services.json.
#
# Licencia: MIT
# ==========================================================

# ==============================================================================
# METADATOS DEL SERVICIO
# ==============================================================================

APP="<Nombre del Servicio>"     # Nombre legible (ej. "AdGuard Home")
APP_ID="<service_id>"           # ID en minúsculas, coincide con filename (ej. "adguard")
CATEGORY="<categoría>"          # Categoría en services.json (ej. "networking")
IMAGE="<imagen:tag>"            # Imagen Docker (ej. "adguard/adguardhome:latest")
PORT_WEB="${PORT_WEB:-<puerto>}" # Puerto web UI por defecto (ej. 3000)

# Recursos por defecto
var_cpu="${var_cpu:-1}"
var_ram="${var_ram:-512M}"

# Redes requeridas (dejar vacío si no necesita)
NETWORKS=()                     # ej. ("iot_net" "db_net")

# ==============================================================================
# FUNCIÓN DE INSTALACIÓN (requerida)
# ==============================================================================

install_service() {
    local svc_dir="${DOCKER_DIR}/${APP_ID}"

    # ── Paso 1: Crear directorios ─────────────────────────────
    msg_info "Creando directorios para ${APP}"
    mkdir -p "${svc_dir}/data"
    # Agregar más subdirectorios según necesidad:
    # mkdir -p "${svc_dir}/data/config"
    # mkdir -p "${svc_dir}/data/logs"
    msg_ok "Directorios creados 📁"

    # ── Paso 2: Crear redes (si se necesitan) ─────────────────
    for net in "${NETWORKS[@]}"; do
        ensure_network "$net"
    done

    # ── Paso 3: Generar archivo .env ──────────────────────────
    msg_info "Generando .env"
    cat > "${svc_dir}/.env" <<EOF
# Variables de entorno de ${APP}
# Generado por DebMenux el $(date -u +"%Y-%m-%d")
TZ=${TZ:-America/La_Paz}

# Agregar secretos aquí:
# EXAMPLE_PASSWORD=$(generate_password)
EOF
    secure_env "${svc_dir}/.env"
    msg_ok ".env creado 🔑"

    # ── Paso 4: Generar compose.yml ───────────────────────────
    msg_info "Generando compose.yml"
    cat > "${svc_dir}/compose.yml" <<EOF
# ${APP} — gestionado por DebMenux
services:
  ${APP_ID}:
    image: ${IMAGE}
    container_name: ${APP_ID}
    restart: unless-stopped
    env_file: .env
    ports:
      - "${PORT_WEB}:${PORT_WEB}"
    volumes:
      - ./data:/data
    deploy:
      resources:
        limits:
          cpus: '${var_cpu}'
          memory: ${var_ram}
    security_opt:
      - no-new-privileges:true
    cap_drop: [ALL]
    # cap_add: [CHOWN, DAC_OVERRIDE, SETUID, SETGID]  # Descomentar si necesario
EOF
    msg_ok "compose.yml creado 📄"

    # ── Paso 5: Permisos ──────────────────────────────────────
    # chmod/chown DESPUÉS de que los archivos existan (nunca antes del mkdir)
    # Ejemplo: chown -R 1000:1000 "${svc_dir}/data"

    # ── Paso 6: Iniciar servicio ──────────────────────────────
    msg_info "Iniciando ${APP}"
    docker compose -f "${svc_dir}/compose.yml" up -d
    msg_ok "${APP} iniciado 🟢"

    # ── Paso 7: Mostrar info de acceso ────────────────────────
    local server_ip
    server_ip=$(get_server_ip)

    echo -e ""
    msg_success "${APP} instalado exitosamente!"
    echo -e "${TAB}${BOLD}🌐 Acceso:${CL} ${BL}http://${server_ip}:${PORT_WEB}${CL}"
    echo -e ""

    # ── Paso 8: Registrar en catálogo externo (si integración habilitada)
    register_to_catalog
}

# ==============================================================================
# FUNCIÓN DE ACTUALIZACIÓN (opcional — fallback es pull+recrear)
# ==============================================================================

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

# ==============================================================================
# FUNCIÓN DE DESINSTALACIÓN (opcional)
# ==============================================================================

# uninstall_service() {
#     local svc_dir="${DOCKER_DIR}/${APP_ID}"
#     svc_down "$APP_ID"
#     echo -e "${TAB}${YWB}⚠️  Los datos permanecen en: ${svc_dir}/data${CL}"
#     echo -e "${TAB}Eliminar manualmente con: rm -rf ${svc_dir}"
# }
