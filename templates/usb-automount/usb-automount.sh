#!/bin/bash
# ==========================================================
# DebMenux — Script de Automontaje/Desmontaje USB
# ==========================================================
# Versión unificada que combina:
#   - USB-AutoMount-Linux (funcionalidad base probada)
#   - Automontaje-MSA (seguridad, whitelist/blacklist, logging)
#
# Uso: usb-automount.sh <dispositivo> <add|remove>
# Llamado automáticamente por systemd via udev.
#
# Licencia: MIT
# ==========================================================

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# ==============================================================================
# CONFIGURACIÓN
# ==============================================================================

CONFIG_FILE="/etc/usb-automount.conf"

# Valores por defecto (sobreescritos por CONFIG_FILE si existe)
MOUNT_BASE="/media"
MIN_SIZE_MB=100
DEFAULT_UID=1000
DEFAULT_GID=1000
LOG_FILE="/var/log/usb-automount.log"
LOG_LEVEL="INFO"
MOUNT_OPTIONS="noexec,nosuid,nodev"
WHITELIST_ENABLED="false"
WHITELIST_FILE="/etc/usb-automount-whitelist.conf"
BLACKLIST_ENABLED="false"
BLACKLIST_FILE="/etc/usb-automount-blacklist.conf"
RATE_LIMIT_MAX=5
RATE_LIMIT_WINDOW=60
TIMEOUT_MOUNT=30
TIMEOUT_UNMOUNT=10
ENABLE_NOTIFICATIONS="false"
MOUNT_OPTIONS_NTFS=""
MOUNT_OPTIONS_VFAT=""
MOUNT_OPTIONS_EXFAT=""
MOUNT_OPTIONS_EXT=""
MOUNT_OPTIONS_BTRFS=""
MOUNT_OPTIONS_XFS=""
MOUNT_OPTIONS_F2FS=""

# Cargar configuración
if [[ -f "$CONFIG_FILE" ]]; then
    # shellcheck source=/dev/null
    source "$CONFIG_FILE"
fi

# ==============================================================================
# LOGGING
# ==============================================================================

readonly _LOG_DEBUG=0 _LOG_INFO=1 _LOG_WARNING=2 _LOG_ERROR=3
_CURRENT_LEVEL=$_LOG_INFO

_init_logger() {
    case "${LOG_LEVEL^^}" in
        DEBUG)   _CURRENT_LEVEL=$_LOG_DEBUG ;;
        INFO)    _CURRENT_LEVEL=$_LOG_INFO ;;
        WARNING) _CURRENT_LEVEL=$_LOG_WARNING ;;
        ERROR)   _CURRENT_LEVEL=$_LOG_ERROR ;;
    esac
    # Crear archivo de log si no existe
    local log_dir
    log_dir=$(dirname "$LOG_FILE")
    [[ -d "$log_dir" ]] || mkdir -p "$log_dir" 2>/dev/null
    touch "$LOG_FILE" 2>/dev/null
}

_log() {
    local level_num="$1" level_name="$2" message="$3"
    if [[ $level_num -ge $_CURRENT_LEVEL ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') [$level_name] [$$] $message" >> "$LOG_FILE"
        logger -t "usb-automount" "[$level_name] $message"
    fi
}

log_debug()   { _log $_LOG_DEBUG   "DEBUG"   "$1"; }
log_info()    { _log $_LOG_INFO    "INFO"    "$1"; }
log_warning() { _log $_LOG_WARNING "WARNING" "$1"; }
log_error()   { _log $_LOG_ERROR   "ERROR"   "$1"; }

# ==============================================================================
# VALIDACIÓN Y SEGURIDAD
# ==============================================================================

# Validar nombre de dispositivo (prevenir inyección)
validate_device_name() {
    local device="$1"
    if ! [[ "$device" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Nombre de dispositivo inválido: $device"
        return 1
    fi
    return 0
}

# Verificar contra blacklist
check_blacklist() {
    local device="$1"
    [[ "$BLACKLIST_ENABLED" != "true" ]] && return 1

    if [[ ! -f "$BLACKLIST_FILE" ]]; then
        return 1
    fi

    # Verificar por nombre
    if grep -qx "$device" "$BLACKLIST_FILE" 2>/dev/null; then
        return 0
    fi

    # Verificar por UUID
    local uuid
    uuid=$(blkid -o value -s UUID "/dev/$device" 2>/dev/null)
    if [[ -n "$uuid" ]] && grep -qx "$uuid" "$BLACKLIST_FILE" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Verificar contra whitelist
check_whitelist() {
    local device="$1"
    [[ "$WHITELIST_ENABLED" != "true" ]] && return 0

    if [[ ! -f "$WHITELIST_FILE" ]]; then
        log_warning "Whitelist habilitada pero archivo no existe: $WHITELIST_FILE"
        return 1
    fi

    # Verificar por nombre
    if grep -qx "$device" "$WHITELIST_FILE" 2>/dev/null; then
        return 0
    fi

    # Verificar por UUID
    local uuid
    uuid=$(blkid -o value -s UUID "/dev/$device" 2>/dev/null)
    if [[ -n "$uuid" ]] && grep -qx "$uuid" "$WHITELIST_FILE" 2>/dev/null; then
        return 0
    fi

    return 1
}

# Rate limiting (prevenir spam de eventos)
check_rate_limit() {
    local device="$1"
    local rate_file="/tmp/usb-automount-rate-${device}"

    # Limpiar archivo antiguo
    if [[ -f "$rate_file" ]]; then
        local file_age
        file_age=$(( $(date +%s) - $(stat -c %Y "$rate_file" 2>/dev/null || echo 0) ))
        if [[ $file_age -gt $RATE_LIMIT_WINDOW ]]; then
            rm -f "$rate_file"
        fi
    fi

    # Contar intentos
    local attempts=0
    if [[ -f "$rate_file" ]]; then
        attempts=$(cat "$rate_file")
    fi
    attempts=$((attempts + 1))

    if [[ $attempts -gt $RATE_LIMIT_MAX ]]; then
        log_warning "Rate limit excedido: $attempts intentos en ${RATE_LIMIT_WINDOW}s para $device"
        return 1
    fi

    echo "$attempts" > "$rate_file"
    return 0
}

# Verificar que no es un symlink malicioso
check_symlink() {
    local path="$1"
    if [[ -L "$path" ]]; then
        local target
        target=$(readlink -f "$path")
        if [[ ! "$target" =~ ^/dev/ ]]; then
            log_error "Symlink sospechoso detectado: $path -> $target"
            return 1
        fi
    fi
    return 0
}

# Verificar tamaño mínimo de partición
check_min_size() {
    local device="$1"
    local partition_size
    partition_size=$(blockdev --getsize64 "/dev/$device" 2>/dev/null)

    if [[ $? -ne 0 || -z "$partition_size" ]]; then
        log_error "No se pudo obtener tamaño de /dev/$device"
        return 1
    fi

    local min_bytes=$((MIN_SIZE_MB * 1024 * 1024))
    if [[ "$partition_size" -lt "$min_bytes" ]]; then
        log_debug "Partición $device demasiado pequeña (${partition_size} bytes < ${min_bytes} bytes)"
        return 1
    fi
    return 0
}

# ==============================================================================
# DETECCIÓN DE FILESYSTEM
# ==============================================================================

detect_filesystem() {
    local device="$1"
    local fs_type
    fs_type=$(blkid -o value -s TYPE "/dev/$device" 2>/dev/null)

    if [[ -z "$fs_type" ]]; then
        log_warning "No se pudo detectar filesystem en /dev/$device con blkid"
        # Fallback con file
        fs_type=$(file -sL "/dev/$device" 2>/dev/null | grep -oiP '(ntfs|fat|exfat|ext[234]|btrfs|xfs|f2fs)' | head -1 | tr '[:upper:]' '[:lower:]')
    fi

    echo "$fs_type"
}

# ==============================================================================
# OPCIONES DE MONTAJE
# ==============================================================================

get_mount_options() {
    local fs_type="$1"
    local opts="$MOUNT_OPTIONS"

    case "$fs_type" in
        ntfs)
            if [[ -n "$MOUNT_OPTIONS_NTFS" ]]; then
                opts="$MOUNT_OPTIONS_NTFS"
            else
                opts="${opts},uid=${DEFAULT_UID},gid=${DEFAULT_GID},umask=022"
            fi
            ;;
        vfat)
            if [[ -n "$MOUNT_OPTIONS_VFAT" ]]; then
                opts="$MOUNT_OPTIONS_VFAT"
            else
                opts="${opts},uid=${DEFAULT_UID},gid=${DEFAULT_GID},umask=022,fmask=133"
            fi
            ;;
        exfat)
            if [[ -n "$MOUNT_OPTIONS_EXFAT" ]]; then
                opts="$MOUNT_OPTIONS_EXFAT"
            else
                opts="${opts},uid=${DEFAULT_UID},gid=${DEFAULT_GID},umask=022"
            fi
            ;;
        ext2|ext3|ext4)
            if [[ -n "$MOUNT_OPTIONS_EXT" ]]; then
                opts="$MOUNT_OPTIONS_EXT"
            else
                opts="${opts}"
            fi
            ;;
        btrfs)
            if [[ -n "$MOUNT_OPTIONS_BTRFS" ]]; then
                opts="$MOUNT_OPTIONS_BTRFS"
            else
                opts="${opts}"
            fi
            ;;
        xfs)
            if [[ -n "$MOUNT_OPTIONS_XFS" ]]; then
                opts="$MOUNT_OPTIONS_XFS"
            else
                opts="${opts}"
            fi
            ;;
        f2fs)
            if [[ -n "$MOUNT_OPTIONS_F2FS" ]]; then
                opts="$MOUNT_OPTIONS_F2FS"
            else
                opts="${opts}"
            fi
            ;;
        *)
            opts="${opts}"
            ;;
    esac

    echo "$opts"
}

# ==============================================================================
# MONTAJE
# ==============================================================================

do_mount() {
    local device="$1"
    local device_path="/dev/$device"
    local mountpoint="$MOUNT_BASE/usb-$device"
    local fs_type
    local mount_opts

    # Detectar filesystem
    fs_type=$(detect_filesystem "$device")
    if [[ -z "$fs_type" ]]; then
        log_error "No se pudo detectar filesystem en $device_path"
        return 1
    fi

    # Obtener opciones de montaje
    mount_opts=$(get_mount_options "$fs_type")

    # Crear punto de montaje
    if ! mkdir -p "$mountpoint" 2>/dev/null; then
        log_error "No se pudo crear directorio $mountpoint"
        return 1
    fi

    # Verificar si ya está montado
    if mountpoint -q "$mountpoint" 2>/dev/null; then
        log_warning "$device_path ya está montado en $mountpoint"
        return 0
    fi

    log_info "Montando $device_path ($fs_type) en $mountpoint con opciones: $mount_opts"

    # Intentar montaje con tipo específico
    local mount_cmd
    case "$fs_type" in
        ntfs)
            if command -v ntfs-3g &>/dev/null; then
                mount_cmd="mount -t ntfs-3g -o $mount_opts $device_path $mountpoint"
            else
                log_warning "ntfs-3g no instalado, intentando montaje kernel"
                mount_cmd="mount -t ntfs3 -o $mount_opts $device_path $mountpoint"
            fi
            ;;
        *)
            mount_cmd="mount -t $fs_type -o $mount_opts $device_path $mountpoint"
            ;;
    esac

    # Ejecutar con timeout
    if timeout "$TIMEOUT_MOUNT" bash -c "$mount_cmd" 2>/dev/null; then
        log_info "✅ $device_path ($fs_type) montado en $mountpoint"

        # Notificación de escritorio (si habilitada)
        if [[ "$ENABLE_NOTIFICATIONS" == "true" ]] && command -v notify-send &>/dev/null; then
            notify-send "🔌 USB Montado" "$device ($fs_type) → $mountpoint" 2>/dev/null || true
        fi
        return 0
    fi

    # Fallback: montaje automático sin tipo explícito
    log_warning "Montaje con -t $fs_type falló, intentando montaje automático"
    if timeout "$TIMEOUT_MOUNT" mount -o "$mount_opts" "$device_path" "$mountpoint" 2>/dev/null; then
        log_info "✅ $device_path montado en $mountpoint (auto-detect)"
        return 0
    fi

    # Fallback final: montaje sin opciones
    log_warning "Montaje con opciones falló, intentando montaje básico"
    if timeout "$TIMEOUT_MOUNT" mount "$device_path" "$mountpoint" 2>/dev/null; then
        log_info "✅ $device_path montado en $mountpoint (básico)"
        return 0
    fi

    # Todo falló
    log_error "❌ No se pudo montar $device_path ($fs_type) en $mountpoint"
    rmdir "$mountpoint" 2>/dev/null
    return 1
}

# ==============================================================================
# DESMONTAJE
# ==============================================================================

do_umount() {
    local device="$1"
    local device_path="/dev/$device"
    local mountpoint="$MOUNT_BASE/usb-$device"

    log_info "Procesando desmontaje de $device_path"

    if ! mountpoint -q "$mountpoint" 2>/dev/null; then
        log_info "$mountpoint no estaba montado"
        # Limpiar directorio igualmente
        cleanup_mountpoint "$mountpoint"
        return 0
    fi

    # Intento 1: desmontaje normal
    if timeout "$TIMEOUT_UNMOUNT" umount "$mountpoint" 2>/dev/null; then
        log_info "✅ $device_path desmontado de $mountpoint"
        cleanup_mountpoint "$mountpoint"
        send_umount_notification "$device" "$mountpoint"
        return 0
    fi

    # Intento 2: desmontaje forzado
    log_warning "Desmontaje normal falló, intentando forzado"
    if timeout "$TIMEOUT_UNMOUNT" umount -f "$mountpoint" 2>/dev/null; then
        log_info "✅ $device_path desmontado forzadamente"
        cleanup_mountpoint "$mountpoint"
        send_umount_notification "$device" "$mountpoint"
        return 0
    fi

    # Intento 3: desmontaje perezoso (último recurso)
    log_warning "Desmontaje forzado falló, intentando lazy unmount"
    if umount -l "$mountpoint" 2>/dev/null; then
        log_info "✅ $device_path desmontado perezosamente"
        cleanup_mountpoint "$mountpoint"
        send_umount_notification "$device" "$mountpoint"
        return 0
    fi

    log_error "❌ No se pudo desmontar $device_path de $mountpoint"
    return 1
}

# ==============================================================================
# LIMPIEZA
# ==============================================================================

cleanup_mountpoint() {
    local mountpoint="$1"
    if [[ -d "$mountpoint" ]]; then
        if ! mountpoint -q "$mountpoint" 2>/dev/null; then
            if [[ -z "$(ls -A "$mountpoint" 2>/dev/null)" ]]; then
                rmdir "$mountpoint" 2>/dev/null && \
                    log_debug "Directorio $mountpoint eliminado"
            else
                log_warning "Directorio $mountpoint no está vacío, no se elimina"
            fi
        fi
    fi
}

# Limpiar todos los puntos de montaje huérfanos
cleanup_orphaned() {
    log_info "Limpiando puntos de montaje huérfanos..."
    local count=0
    for dir in "$MOUNT_BASE"/usb-*; do
        [[ -d "$dir" ]] || continue
        if ! mountpoint -q "$dir" 2>/dev/null; then
            if [[ -z "$(ls -A "$dir" 2>/dev/null)" ]]; then
                rmdir "$dir" 2>/dev/null && ((count++))
            fi
        fi
    done
    [[ $count -gt 0 ]] && log_info "Eliminados $count puntos de montaje huérfanos"
}

# ==============================================================================
# NOTIFICACIONES
# ==============================================================================

send_umount_notification() {
    local device="$1"
    local mountpoint="$2"
    if [[ "$ENABLE_NOTIFICATIONS" == "true" ]] && command -v notify-send &>/dev/null; then
        notify-send "⏏️ USB Desmontado" "$device desconectado de $mountpoint" 2>/dev/null || true
    fi
}

# Notificación de desconexión insegura (USB retirado sin desmontar)
send_unsafe_disconnect_notification() {
    local device="$1"
    local mountpoint="$2"
    log_warning "⚠️ DESCONEXIÓN INSEGURA: /dev/$device fue retirado sin desmontar de $mountpoint"
    if [[ "$ENABLE_NOTIFICATIONS" == "true" ]] && command -v notify-send &>/dev/null; then
        notify-send -u critical "⚠️ USB Desconexión Insegura" \
            "$device fue retirado sin desmontar.\nPunto: $mountpoint\nEjecuta: usb-automount.sh --cleanup" 2>/dev/null || true
    fi
}

# ==============================================================================
# CLI: --status (USBs montados, formato parseable)
# ==============================================================================

cli_status() {
    local mount_base="$MOUNT_BASE"
    local old_nullglob
    old_nullglob=$(shopt -p nullglob 2>/dev/null || true)
    shopt -s nullglob

    local found=0
    echo "# USB Automount — Estado"
    echo "# mount_base: $mount_base"
    echo "# timestamp: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "#"
    echo "# DISPOSITIVO | PUNTO_MONTAJE | FILESYSTEM | TAMAÑO | ESTADO"

    for dir in "$mount_base"/usb-*; do
        [[ -d "$dir" ]] || continue
        local dev_name
        dev_name=$(basename "$dir" | sed 's/usb-//')

        if mountpoint -q "$dir" 2>/dev/null; then
            local fs_type size
            fs_type=$(findmnt -n -o FSTYPE "$dir" 2>/dev/null || echo "?")
            size=$(findmnt -n -o SIZE "$dir" 2>/dev/null || echo "?")
            echo "$dev_name | $dir | $fs_type | $size | montado"
            found=1
        else
            echo "$dev_name | $dir | - | - | huérfano"
            found=1
        fi
    done

    eval "$old_nullglob" 2>/dev/null || true

    if [[ $found -eq 0 ]]; then
        echo "# (ningún USB detectado)"
    fi
}

# ==============================================================================
# CLI: --list (solo nombres, para scripts/pipes)
# ==============================================================================

cli_list() {
    local mount_base="$MOUNT_BASE"
    local old_nullglob
    old_nullglob=$(shopt -p nullglob 2>/dev/null || true)
    shopt -s nullglob

    for dir in "$mount_base"/usb-*; do
        [[ -d "$dir" ]] || continue
        if mountpoint -q "$dir" 2>/dev/null; then
            basename "$dir"
        fi
    done

    eval "$old_nullglob" 2>/dev/null || true
}

# ==============================================================================
# CLI: --export (empaquetar config para backup/reinstalación)
# ==============================================================================

cli_export() {
    local output="${1:-/tmp/usb-automount-backup.tar.gz}"

    # Verificar que podemos leer los archivos de config
    if [[ ! -r "$CONFIG_FILE" ]]; then
        echo "❌ No se puede leer $CONFIG_FILE (¿permisos? usa sudo)"
        return 1
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d /tmp/usb-automount-export.XXXXXX)

    # Copiar archivos de configuración
    [[ -f "$CONFIG_FILE" ]] && cp "$CONFIG_FILE" "$tmp_dir/usb-automount.conf"
    [[ -f "/etc/usb-automount-whitelist.conf" ]] && cp "/etc/usb-automount-whitelist.conf" "$tmp_dir/whitelist.conf"
    [[ -f "/etc/usb-automount-blacklist.conf" ]] && cp "/etc/usb-automount-blacklist.conf" "$tmp_dir/blacklist.conf"

    # Metadata
    cat > "$tmp_dir/export-info.txt" <<EOF
# USB Automount — Export
# Fecha: $(date -u +"%Y-%m-%dT%H:%M:%SZ")
# Host: $(hostname)
# Versión script: $(grep "^# Version" /usr/local/bin/usb-automount.sh 2>/dev/null | head -1 || echo "unknown")
#
# Para restaurar:
#   usb-automount.sh --import $output
EOF

    # Empaquetar
    tar -czf "$output" -C "$tmp_dir" . 2>/dev/null
    rm -rf "$tmp_dir"

    echo "✅ Config exportada a: $output"
    echo "   Contiene: usb-automount.conf, whitelist.conf, blacklist.conf"
    echo "   Restaurar: usb-automount.sh --import $output"
}

# ==============================================================================
# CLI: --import (restaurar config desde backup)
# ==============================================================================

cli_import() {
    local input="${1:-}"

    # Requiere root para escribir en /etc
    if [[ "$(id -u)" -ne 0 ]]; then
        echo "❌ --import requiere privilegios de root (usa sudo)"
        return 1
    fi

    if [[ -z "$input" || ! -f "$input" ]]; then
        echo "❌ Uso: usb-automount.sh --import <archivo.tar.gz>"
        echo "   Genera uno con: usb-automount.sh --export [ruta]"
        return 1
    fi

    local tmp_dir
    tmp_dir=$(mktemp -d /tmp/usb-automount-import.XXXXXX)

    # Extraer
    if ! tar -xzf "$input" -C "$tmp_dir" 2>/dev/null; then
        echo "❌ Error al extraer: $input"
        rm -rf "$tmp_dir"
        return 1
    fi

    # Verificar que tiene el archivo principal
    if [[ ! -f "$tmp_dir/usb-automount.conf" ]]; then
        echo "❌ Archivo inválido — no contiene usb-automount.conf"
        rm -rf "$tmp_dir"
        return 1
    fi

    # Backup de config actual antes de sobreescribir
    [[ -f "$CONFIG_FILE" ]] && cp "$CONFIG_FILE" "${CONFIG_FILE}.pre-import.bak"

    # Restaurar config principal
    if ! cp "$tmp_dir/usb-automount.conf" "$CONFIG_FILE"; then
        echo "❌ No se pudo escribir $CONFIG_FILE (¿permisos/disco?)"
        rm -rf "$tmp_dir"
        return 1
    fi
    chmod 644 "$CONFIG_FILE"
    echo "✅ Restaurado: $CONFIG_FILE"

    # Restaurar whitelist
    if [[ -f "$tmp_dir/whitelist.conf" ]]; then
        if cp "$tmp_dir/whitelist.conf" "/etc/usb-automount-whitelist.conf"; then
            echo "✅ Restaurado: /etc/usb-automount-whitelist.conf"
        else
            echo "⚠️  No se pudo restaurar whitelist.conf"
        fi
    fi

    # Restaurar blacklist
    if [[ -f "$tmp_dir/blacklist.conf" ]]; then
        if cp "$tmp_dir/blacklist.conf" "/etc/usb-automount-blacklist.conf"; then
            echo "✅ Restaurado: /etc/usb-automount-blacklist.conf"
        else
            echo "⚠️  No se pudo restaurar blacklist.conf"
        fi
    fi

    # Mostrar info del export
    if [[ -f "$tmp_dir/export-info.txt" ]]; then
        echo ""
        echo "📋 Info del backup:"
        grep -v "^#.*Para restaurar" "$tmp_dir/export-info.txt" | grep -v "^#.*usb-automount" | grep "^#" | sed 's/^# /   /'
    fi

    rm -rf "$tmp_dir"

    # Recargar config
    echo ""
    echo "🔄 Recargando udev..."
    udevadm control --reload-rules 2>/dev/null || true
    echo "✅ Importación completada. La config está activa."
}

# ==============================================================================
# PUNTO DE ENTRADA
# ==============================================================================

main() {
    _init_logger

    # ── CLI flags (no requieren dispositivo como argumento) ────
    case "${1:-}" in
        --status)
            cli_status
            exit 0
            ;;
        --list)
            cli_list
            exit 0
            ;;
        --cleanup)
            cleanup_orphaned
            exit 0
            ;;
        --export)
            cli_export "${2:-/tmp/usb-automount-backup.tar.gz}"
            exit 0
            ;;
        --import)
            cli_import "${2:-}"
            exit $?
            ;;
        --help|-h)
            echo "USB Automount — Gestión de dispositivos USB"
            echo ""
            echo "Uso automático (via udev/systemd):"
            echo "  usb-automount.sh <dispositivo> <add|remove>"
            echo ""
            echo "Uso manual (CLI):"
            echo "  usb-automount.sh --status      Mostrar USBs montados (parseable)"
            echo "  usb-automount.sh --list        Solo nombres de USBs montados"
            echo "  usb-automount.sh --cleanup     Limpiar puntos de montaje huérfanos"
            echo "  usb-automount.sh --export [f]  Exportar config a archivo (.tar.gz)"
            echo "  usb-automount.sh --import <f>  Importar config desde backup"
            echo "  usb-automount.sh --help        Mostrar esta ayuda"
            exit 0
            ;;
    esac

    # ── Modo normal: dispositivo + acción (llamado por systemd) ─
    local device="${1:-}"
    local action="${2:-}"

    # Validar argumentos
    if [[ -z "$device" || -z "$action" ]]; then
        log_error "Uso: $0 <dispositivo> <add|remove|cleanup> | --status | --list | --cleanup | --export | --import"
        exit 1
    fi

    # Acción especial legacy: cleanup (compatible con timer)
    if [[ "$action" == "cleanup" ]]; then
        cleanup_orphaned
        exit 0
    fi

    # Validar nombre del dispositivo
    if ! validate_device_name "$device"; then
        exit 1
    fi

    # Verificar que /dev/device existe (para add)
    if [[ "$action" == "add" && ! -b "/dev/$device" ]]; then
        log_error "Dispositivo /dev/$device no existe o no es dispositivo de bloque"
        exit 1
    fi

    # Verificar symlinks
    if ! check_symlink "/dev/$device"; then
        exit 1
    fi

    # Rate limiting
    if ! check_rate_limit "$device"; then
        exit 1
    fi

    # Crear directorio base si no existe
    mkdir -p "$MOUNT_BASE" 2>/dev/null

    case "$action" in
        add)
            log_info "═══ MONTAJE: /dev/$device ═══"

            # Root monta cualquier USB — whitelist/blacklist solo aplica a usuarios
            if [[ "$(id -u)" -ne 0 ]]; then
                # Verificar blacklist
                if check_blacklist "$device"; then
                    log_warning "Dispositivo $device en blacklist — denegado (usuario: $(whoami))"
                    exit 0
                fi

                # Verificar whitelist
                if ! check_whitelist "$device"; then
                    log_warning "Dispositivo $device no autorizado — whitelist activa (usuario: $(whoami))"
                    exit 0
                fi
            else
                log_debug "Root detectado — saltando whitelist/blacklist"
            fi

            # Verificar tamaño mínimo
            if ! check_min_size "$device"; then
                log_info "Partición $device demasiado pequeña, ignorando"
                exit 0
            fi

            # Montar
            do_mount "$device"
            ;;

        remove)
            log_info "═══ DESMONTAJE: /dev/$device ═══"

            local mountpoint="$MOUNT_BASE/usb-$device"

            # Detectar desconexión insegura: mount sigue activo pero dispositivo ya no existe
            if mountpoint -q "$mountpoint" 2>/dev/null && [[ ! -b "/dev/$device" ]]; then
                send_unsafe_disconnect_notification "$device" "$mountpoint"
            fi

            do_umount "$device"
            ;;

        *)
            log_error "Acción no válida: $action. Usa: add|remove|cleanup"
            exit 1
            ;;
    esac
}

main "$@"
exit $?
