#!/usr/bin/env bash
# ==========================================================
# DebMenux — Toolkit interactivo para homelab Debian + Docker
# ==========================================================
# Archivo: lib/integration.sh
# Descripción: Capa de integración entre DebMenux y repos
#              de configuración externos (ej. nas-dotfiles).
#
# Este módulo es OPCIONAL — DebMenux funciona standalone.
# Cuando se encuentra debmenux.conf, habilita:
#   - Auto-registro de servicios instalados al catálogo
#   - Carga de variables globales .env (SERVER_IP, TZ)
#   - Lectura de rutas configurables por usuario (sin hardcodear)
#
# Orden de detección de debmenux.conf:
#   1. $DEBMENUX_CONF (variable de entorno explícita)
#   2. /etc/debmenux/debmenux.conf (a nivel de sistema)
#   3. $HOME/.config/debmenux/debmenux.conf (a nivel de usuario)
#
# Licencia: MIT
# ==========================================================

[[ -n "${__DEBMENUX_INTEGRATION_LOADED:-}" ]] && return 0
__DEBMENUX_INTEGRATION_LOADED=1

# ==============================================================================
# SECCIÓN 1: DESCUBRIMIENTO DE CONFIGURACIÓN
# ==============================================================================

# Ruta al config de integración (se establece tras detección)
DEBMENUX_CONF="${DEBMENUX_CONF:-}"

# Rutas detectadas (se llenan con load_integration_config)
INTEGRATION_ENABLED=false
INTEGRATION_DOTFILES_DIR=""
INTEGRATION_CATALOG_DIR=""
INTEGRATION_GLOBAL_ENV=""
INTEGRATION_DOCKER_DIR=""

# Localizar y cargar debmenux.conf
load_integration_config() {
    # Orden de búsqueda
    local search_paths=(
        "${DEBMENUX_CONF}"
        "/etc/debmenux/debmenux.conf"
        "${HOME}/.config/debmenux/debmenux.conf"
    )

    for conf_path in "${search_paths[@]}"; do
        if [[ -n "$conf_path" && -f "$conf_path" ]]; then
            DEBMENUX_CONF="$conf_path"
            break
        fi
    done

    # No encontrado — integración deshabilitada (DebMenux funciona igual)
    if [[ -z "$DEBMENUX_CONF" || ! -f "$DEBMENUX_CONF" ]]; then
        INTEGRATION_ENABLED=false
        return 0
    fi

    # Parsear archivo (KEY=VALUE simple, sin eval por seguridad)
    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue

        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Expandir ~ y $HOME en valor
        value="${value/#\~/$HOME}"
        value="${value/\$HOME/$HOME}"

        case "$key" in
            DOTFILES_DIR)     INTEGRATION_DOTFILES_DIR="$value" ;;
            CATALOG_DIR)      INTEGRATION_CATALOG_DIR="$value" ;;
            GLOBAL_ENV)       INTEGRATION_GLOBAL_ENV="$value" ;;
            DOCKER_DIR)       INTEGRATION_DOCKER_DIR="$value" ;;
        esac
    done < "$DEBMENUX_CONF" || true

    # Validar requisito mínimo
    if [[ -n "$INTEGRATION_DOTFILES_DIR" && -d "$INTEGRATION_DOTFILES_DIR" ]]; then
        INTEGRATION_ENABLED=true

        # Aplicar DOCKER_DIR del config si no fue seteado por CLI
        if [[ -n "$INTEGRATION_DOCKER_DIR" && "$DOCKER_DIR" == "/docker" ]]; then
            DOCKER_DIR="$INTEGRATION_DOCKER_DIR"
        fi

        # Ruta de catálogo por defecto si no se especificó
        if [[ -z "$INTEGRATION_CATALOG_DIR" ]]; then
            INTEGRATION_CATALOG_DIR="${INTEGRATION_DOTFILES_DIR}/agent/catalog/services"
        fi

        # Ruta de env global por defecto si no se especificó
        if [[ -z "$INTEGRATION_GLOBAL_ENV" && -n "$INTEGRATION_DOCKER_DIR" ]]; then
            INTEGRATION_GLOBAL_ENV="${INTEGRATION_DOCKER_DIR}/.env"
        fi
    fi

    return 0
}

# ==============================================================================
# SECCIÓN 2: ENTORNO GLOBAL
# ==============================================================================

# Cargar .env global (SERVER_IP, TZ, etc.) si la integración está habilitada
load_global_env() {
    local env_file="${INTEGRATION_GLOBAL_ENV:-${DOCKER_DIR}/.env}"

    if [[ ! -f "$env_file" ]]; then
        return 0
    fi

    while IFS='=' read -r key value; do
        [[ "$key" =~ ^[[:space:]]*# ]] && continue
        [[ -z "$key" ]] && continue
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)

        # Solo exportar vars en mayúsculas que parecen configuración
        if [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
            export "$key=$value"
        fi
    done < "$env_file" || true
}

# ==============================================================================
# SECCIÓN 3: REGISTRO EN CATÁLOGO
# ==============================================================================

# Registrar un servicio instalado en el catálogo externo.
# Se llama al final de cada script de instalación.
#
# Uso: register_to_catalog
#
# Requiere estas variables del script de servicio:
#   APP, APP_ID, CATEGORY, IMAGE, var_cpu, var_ram
#   PORT_WEB (o vars de puerto específicas)
#   NETWORKS (array, opcional)
#
# Lo que crea:
#   $CATALOG_DIR/<APP_ID>/ficha.md      — metadatos del servicio
#   $CATALOG_DIR/<APP_ID>/compose.yml   — copia del compose instalado
#   $CATALOG_DIR/<APP_ID>/.env.example  — template de env sanitizado
#
register_to_catalog() {
    # Omitir si la integración no está habilitada
    if [[ "$INTEGRATION_ENABLED" != "true" ]]; then
        return 0
    fi

    local catalog_dir="${INTEGRATION_CATALOG_DIR}"

    # Validar que el directorio del catálogo existe
    if [[ ! -d "$catalog_dir" ]]; then
        mkdir -p "$catalog_dir" 2>/dev/null || return 0
    fi

    local svc_dir="${DOCKER_DIR}/${APP_ID}"
    local target_dir="${catalog_dir}/${APP_ID}"

    msg_info "📋 Registrando ${APP} en el catálogo"

    # Crear directorio de entrada en catálogo
    mkdir -p "$target_dir"

    # ── Generar ficha.md ──────────────────────────────────────
    _generate_ficha "$target_dir"

    # ── Copiar compose.yml adaptando rutas relativas del catálogo ────────
    if [[ -f "${svc_dir}/compose.yml" ]]; then
        # El compose desplegado usa ../_common.yml; el catálogo necesita ../../.
        sed -E \
            's#^([[:space:]]*file:[[:space:]]*)\.\./_common\.yml([[:space:]]*)$#\1../../_common.yml\2#' \
            "${svc_dir}/compose.yml" > "${target_dir}/compose.yml"
    fi

    # ── Generar .env.example (secretos reemplazados) ──────────
    _generate_env_example "$target_dir" "$svc_dir"

    # ── Generar guía placeholder (si no existe) ───────────────
    _generate_guide_placeholder "$target_dir" "$svc_dir"

    # ── Notificar via ntfy ────────────────────────────────────
    _notify_catalog_registration

    msg_ok "📋 ${APP} registrado en catálogo (${target_dir})"
}

# Generar ficha.md para un servicio
_generate_ficha() {
    local target_dir="$1"

    # No sobrescribir una ficha manual o corregida: conserva conocimiento operativo
    # específico que no puede regenerarse de forma segura desde el script.
    if [[ -f "${target_dir}/ficha.md" ]]; then
        msg_info "Ficha existente conservada para ${APP_ID}"
        return 0
    fi

    local port_main="${PORT_WEB:-${PORT_MQTT:-${PORT_ADMIN:-0}}}"

    local networks_yaml=""
    if [[ ${#NETWORKS[@]:-0} -gt 0 ]]; then
        networks_yaml=$(printf "  - %s\n" "${NETWORKS[@]}")
    fi

    local volumes_yaml=""
    if [[ -f "${DOCKER_DIR}/${APP_ID}/compose.yml" ]]; then
        volumes_yaml=$(grep -E "^\s+- \./.*:.*" "${DOCKER_DIR}/${APP_ID}/compose.yml" 2>/dev/null | sed 's/^[[:space:]]*/  /' || true)
    fi

    local env_list=""
    if [[ -f "${DOCKER_DIR}/${APP_ID}/.env" ]]; then
        env_list=$(grep -v '^#' "${DOCKER_DIR}/${APP_ID}/.env" | grep -v '^$' | cut -d= -f1 | sed 's/^/  - /' || true)
    fi

    cat > "${target_dir}/ficha.md" <<EOF
---
id: "${APP_ID}"
name: "${APP}"
description: "Instalado por DebMenux"
aliases:
  - ${APP_ID}
image: "${IMAGE}"
category: "${CATEGORY}"
port_default: ${port_main}
protocol: "http"
needs_proxy: false
needs_db: false
env_required:
${env_list}
backup_critical: true
backup_paths:
  - "./data"
protected: false
docs_url: ""
notes: "Auto-registrado por DebMenux register_to_catalog()"
$(if [[ -n "$networks_yaml" ]]; then
echo "networks:"
echo "$networks_yaml"
fi)
---

# ${APP}

## Qué es

(Auto-registrado por DebMenux — completar manualmente)

## Configuración detectada

- Imagen: \`${IMAGE}\`
- Puerto: ${port_main}
- Categoría: ${CATEGORY}
- Instalado: $(date -u +"%Y-%m-%d")
$(if [[ ${#NETWORKS[@]:-0} -gt 0 ]]; then
echo "- Redes: ${NETWORKS[*]}"
fi)

## Notas

- Ficha generada automáticamente por DebMenux
- Editar para agregar documentación operativa
- Para guía completa: crear docs/services/${APP_ID}-guide.md
EOF
}

# Generar .env.example (reemplazar valores secretos con __pega_aqui__)
_generate_env_example() {
    local target_dir="$1"
    local svc_dir="$2"

    if [[ ! -f "${svc_dir}/.env" ]]; then
        return 0
    fi

    if [[ -f "${target_dir}/.env.example" ]]; then
        msg_info ".env.example existente conservado para ${APP_ID}"
        return 0
    fi

    local secret_patterns="PASSWORD|SECRET|TOKEN|COOKIE|KEY|PASS"

    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]*# ]] || [[ -z "$line" ]]; then
            echo "$line"
        elif [[ "$line" =~ ^([A-Z_]+)= ]]; then
            local key="${BASH_REMATCH[1]}"
            if [[ "$key" =~ ($secret_patterns) ]]; then
                echo "${key}=__pega_aqui__"
            else
                echo "$line"
            fi
        else
            echo "$line"
        fi
    done < "${svc_dir}/.env" > "${target_dir}/.env.example"
}

# ==============================================================================
# SECCIÓN 4: GUÍA PLACEHOLDER (cascada)
# ==============================================================================

# Generar guía operativa placeholder si no existe
_generate_guide_placeholder() {
    local target_dir="$1"
    local svc_dir="$2"

    local docs_dir="${INTEGRATION_DOTFILES_DIR}/docs/services"
    local guide_file="${docs_dir}/${APP_ID}-guide.md"

    # Solo generar si la integración está habilitada y el dir de docs existe
    if [[ -z "$INTEGRATION_DOTFILES_DIR" ]]; then
        return 0
    fi

    # No sobreescribir guías existentes
    if [[ -f "$guide_file" ]]; then
        return 0
    fi

    mkdir -p "$docs_dir"

    local port_main="${PORT_WEB:-${PORT_MQTT:-${PORT_ADMIN:-0}}}"

    cat > "$guide_file" <<EOF
# ${APP} — Guía Operativa

> **Puerto:** ${port_main}
> **Imagen:** ${IMAGE}
> **Red:** ${NETWORKS[*]:-bridge}
> **Instalado por:** DebMenux (\`scripts/services/${APP_ID}.sh\`)
> **Tipo:** Docker container

---

## Qué es

_(Completar: qué hace este servicio y por qué está en el NAS)_

---

## Instalación

\`\`\`bash
debmenu install ${APP_ID}
# O manualmente:
mkdir -p \$dkco/${APP_ID}/data
dk ${APP_ID} && svc up ${APP_ID}
\`\`\`

---

## Configuración

_(Completar: parámetros importantes del .env, config files especiales)_

---

## Backup y recuperación

\`\`\`bash
svc backup ${APP_ID}
\`\`\`

_(Completar: qué respaldar, frecuencia, cómo restaurar)_

---

## Troubleshooting

_(Completar: errores encontrados y cómo se resolvieron)_

---

> **Nota:** Guía generada automáticamente por DebMenux al instalar \`${APP_ID}\`.
> Completar con información operativa real según se use el servicio.
> Generado: $(date -u +"%Y-%m-%d")
EOF

    msg_ok "📝 Guía placeholder creada: ${guide_file}"
}

# ==============================================================================
# SECCIÓN 5: NOTIFICACIONES (cascada)
# ==============================================================================

# Notificar que se registró un servicio (si ntfy disponible)
_notify_catalog_registration() {
    local ntfy_url="${NTFY_URL:-}"

    # Intentar cargar NTFY_URL de /etc/environment si no está en el entorno
    if [[ -z "$ntfy_url" && -f /etc/environment ]]; then
        ntfy_url=$(grep -m1 "^NTFY_URL=" /etc/environment 2>/dev/null | cut -d= -f2)
    fi

    [[ -z "$ntfy_url" ]] && return 0

    local port_main="${PORT_WEB:-${PORT_MQTT:-${PORT_ADMIN:-0}}}"

    curl -s --max-time 5 \
        -H "Title: 📋 Servicio registrado: ${APP}" \
        -H "Tags: books,whale" \
        -d "DebMenux registró ${APP_ID} en el catálogo. Puerto: ${port_main}. Ficha + guía generadas." \
        "${ntfy_url}/docker" \
        >/dev/null 2>&1 || true
}

# ==============================================================================
# SECCIÓN 6: CONSULTA DE CATÁLOGO
# ==============================================================================

# Verificar si un servicio está registrado en el catálogo
is_registered() {
    local service_id="$1"
    [[ "$INTEGRATION_ENABLED" == "true" ]] && \
    [[ -f "${INTEGRATION_CATALOG_DIR}/${service_id}/ficha.md" ]]
}

# ==============================================================================
# SECCIÓN 7: INICIALIZACIÓN
# ==============================================================================

# Auto-cargar integración al hacer source
load_integration_config
load_global_env
