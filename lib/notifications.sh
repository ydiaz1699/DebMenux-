#!/usr/bin/env bash
# ==========================================================
# DebMenux — Librería de Notificaciones (ntfy)
# ==========================================================
# Archivo: lib/notifications.sh
# Descripción: Función ntfy_send() compartida por todos los
#              scripts de DebMenux. Envía notificaciones push
#              al servidor ntfy local.
#
# Uso:
#   source "$DEBMENUX_BASE_DIR/lib/notifications.sh"
#   ntfy_send "topic" "Título" "Mensaje" "prioridad" "tags"
#
# Topics sugeridos:
#   usb      → automontaje/desmontaje de USBs
#   docker   → eventos de servicios Docker
#   backups  → backups (cron, manual)
#   system   → SMART, SSH login, disco lleno
#   alarma   → alarma + cámara (Home Assistant)
#   nas-alerts → catch-all
#
# Prioridades: min, low, default, high, urgent
#
# Licencia: MIT
# ==========================================================

# Evitar doble source
[[ -n "${__DEBMENUX_NOTIFICATIONS_LOADED:-}" ]] && return 0
__DEBMENUX_NOTIFICATIONS_LOADED=1

# ==============================================================================
# CONFIGURACIÓN
# ==============================================================================

# Se puede sobreescribir via /etc/usb-automount.conf, .env, o variable de entorno
NTFY_URL="${NTFY_URL:-http://localhost:8090}"
NTFY_DEFAULT_TOPIC="${NTFY_DEFAULT_TOPIC:-nas-alerts}"

# ==============================================================================
# FUNCIÓN PRINCIPAL
# ==============================================================================

# ntfy_send — Enviar notificación push via ntfy
#
# Argumentos:
#   $1 — topic (default: nas-alerts)
#   $2 — título (opcional)
#   $3 — mensaje/body (requerido)
#   $4 — prioridad: min|low|default|high|urgent (default: default)
#   $5 — tags/emojis (ej. "warning,usb" → se muestran como iconos en la app)
#
# Variables de entorno opcionales:
#   NTFY_URL    — URL base del servidor (default: http://localhost:8090)
#   NTFY_TOKEN  — Token de autenticación (si el servidor lo requiere)
#
# Retorno: siempre 0 (fallo silencioso para no romper el llamador)
#
ntfy_send() {
    local topic="${1:-$NTFY_DEFAULT_TOPIC}"
    local title="${2:-}"
    local message="${3:-}"
    local priority="${4:-default}"
    local tags="${5:-}"

    # Si no hay mensaje, no enviar nada
    [[ -z "$message" ]] && return 0

    # Construir headers
    local -a headers=()
    [[ -n "$title" ]] && headers+=(-H "Title: $title")
    [[ -n "$priority" && "$priority" != "default" ]] && headers+=(-H "Priority: $priority")
    [[ -n "$tags" ]] && headers+=(-H "Tags: $tags")

    # Auth token (si está configurado)
    [[ -n "${NTFY_TOKEN:-}" ]] && headers+=(-H "Authorization: Bearer $NTFY_TOKEN")

    # Enviar (silencioso, timeout 5s, no romper si falla)
    curl -s --max-time 5 \
        "${headers[@]}" \
        -d "$message" \
        "${NTFY_URL}/${topic}" \
        >/dev/null 2>&1 || true
}

# ==============================================================================
# FUNCIONES DE CONVENIENCIA
# ==============================================================================

# Notificación de USB montado
ntfy_usb_mounted() {
    local device="$1"
    local mountpoint="$2"
    local fs_type="${3:-}"
    ntfy_send "usb" "🔌 USB Montado" \
        "${device} (${fs_type}) → ${mountpoint}" \
        "default" "usb,mount"
}

# Notificación de USB desmontado
ntfy_usb_unmounted() {
    local device="$1"
    local mountpoint="$2"
    ntfy_send "usb" "⏏️ USB Desmontado" \
        "${device} desconectado de ${mountpoint}" \
        "default" "usb,eject"
}

# Notificación de desconexión insegura
ntfy_usb_unsafe() {
    local device="$1"
    local mountpoint="$2"
    ntfy_send "usb" "⚠️ Desconexión Insegura" \
        "${device} retirado sin desmontar de ${mountpoint}. Ejecutar: usb-automount.sh --cleanup" \
        "high" "warning,usb"
}

# Notificación de servicio Docker
ntfy_docker_event() {
    local service="$1"
    local event="$2"
    local details="${3:-}"
    ntfy_send "docker" "${event}: ${service}" \
        "$details" \
        "high" "whale,warning"
}

# Notificación de backup completado
ntfy_backup_complete() {
    local service="$1"
    local size="${2:-}"
    ntfy_send "backups" "✅ Backup ${service}" \
        "Completado${size:+: ${size}}" \
        "default" "floppy_disk"
}

# Notificación del sistema (crítica)
ntfy_system_alert() {
    local title="$1"
    local message="$2"
    local priority="${3:-high}"
    ntfy_send "system" "$title" "$message" "$priority" "rotating_light"
}
