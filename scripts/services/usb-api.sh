#!/usr/bin/env bash
# ==========================================================
# DebMenux — Servicio: USB API
# ==========================================================
# Descripción: Mini API REST para listar y desmontar USBs
#              desde la web (Homepage widget). Se instala como
#              servicio systemd NATIVO (no Docker) porque
#              necesita ejecutar umount en el host.
#
# Endpoints:
#   GET  /usb/list         → JSON de USBs montados
#   POST /usb/unmount/:dev → Desmonta USB de forma segura
#   GET  /health           → Health check
#
# Puerto: 8091 (solo LAN)
# Licencia: MIT
# ==========================================================

# ==============================================================================
# METADATOS DEL SERVICIO
# ==============================================================================

APP="USB API"
APP_ID="usb-api"
CATEGORY="management"
PORT_WEB="${PORT_WEB:-8091}"

# Recursos (N/A — es un servicio nativo, no Docker)
var_cpu="N/A"
var_ram="N/A"

# ==============================================================================
# INSTALACIÓN
# ==============================================================================

install_service() {
    local server_ip
    server_ip=$(get_server_ip)

    # ── Paso 1: Verificar dependencias ────────────────────────
    msg_info "Verificando dependencias"
    ensure_package "python3"
    # http.server está en la stdlib, no necesita pip
    msg_ok "Dependencias OK 📦"

    # ── Paso 2: Crear directorio de la app ────────────────────
    msg_info "Creando directorio de la aplicación"
    mkdir -p /usr/local/lib/usb-api
    msg_ok "Directorio creado 📁"

    # ── Paso 3: Crear script Python del servidor ──────────────
    msg_info "Instalando servidor USB API"
    cat > /usr/local/lib/usb-api/server.py <<'PYEOF'
#!/usr/bin/env python3
"""
USB API — Mini servidor REST para gestión de dispositivos USB.

Endpoints:
  GET  /usb/list         → Lista USBs montados (JSON)
  POST /usb/unmount/:dev → Desmonta un USB de forma segura
  GET  /health           → Health check

Diseñado para correr como servicio systemd en el host.
No requiere dependencias externas (usa stdlib http.server).
"""

import json
import os
import re
import subprocess
import sys
from http.server import HTTPServer, BaseHTTPRequestHandler
from urllib.parse import urlparse

# Configuración
BIND_ADDR = os.environ.get("USB_API_BIND", "0.0.0.0")
PORT = int(os.environ.get("USB_API_PORT", "8091"))
MOUNT_BASE = os.environ.get("MOUNT_BASE", "/NAS/USB")
NTFY_URL = os.environ.get("NTFY_URL", "http://localhost:8090")


def get_mounted_usbs():
    """Obtener lista de USBs montados bajo MOUNT_BASE."""
    usbs = []
    try:
        result = subprocess.run(
            ["findmnt", "-J", "-l", "-o", "SOURCE,TARGET,FSTYPE,SIZE,USED,AVAIL,USE%"],
            capture_output=True, text=True, timeout=5
        )
        if result.returncode != 0:
            return usbs

        data = json.loads(result.stdout)
        for fs in data.get("filesystems", []):
            target = fs.get("target", "")
            # Solo listar subdirectorios dentro de MOUNT_BASE (no el propio MOUNT_BASE)
            # Soporta tanto /NAS/USB/usb-sdb1 como /NAS/USB/MI_PENDRIVE (por label)
            if target.startswith(MOUNT_BASE + "/") and target != MOUNT_BASE:
                # Extraer nombre del dispositivo del source
                source = fs.get("source", "")
                dev_name = os.path.basename(source) if source.startswith("/dev/") else source
                usbs.append({
                    "device": dev_name,
                    "source": source,
                    "mountpoint": target,
                    "fstype": fs.get("fstype", ""),
                    "size": fs.get("size", ""),
                    "used": fs.get("used", ""),
                    "avail": fs.get("avail", ""),
                    "use_percent": fs.get("use%", ""),
                })
    except (subprocess.TimeoutExpired, json.JSONDecodeError, FileNotFoundError):
        pass
    return usbs


def unmount_device(device_name):
    """Desmontar un dispositivo USB de forma segura.

    Args:
        device_name: Nombre del dispositivo (ej. 'sdb1', 'usb-sdb1')

    Returns:
        tuple: (success: bool, message: str)
    """
    # Sanitizar nombre del dispositivo
    clean_name = re.sub(r'[^a-zA-Z0-9_-]', '', device_name)
    if not clean_name:
        return False, "Nombre de dispositivo inválido"

    # Buscar el mountpoint correspondiente
    mountpoint = None
    for usb in get_mounted_usbs():
        if usb["device"] == clean_name or \
           usb["mountpoint"].endswith(f"usb-{clean_name}") or \
           usb["mountpoint"].endswith(f"/{clean_name}"):
            mountpoint = usb["mountpoint"]
            break

    if not mountpoint:
        # Intentar construir el path directamente (por label o por usb-device)
        for candidate in [
            os.path.join(MOUNT_BASE, clean_name),
            os.path.join(MOUNT_BASE, f"usb-{clean_name}"),
        ]:
            if os.path.ismount(candidate):
                mountpoint = candidate
                break

        if not mountpoint:
            return False, f"Dispositivo '{clean_name}' no encontrado o no montado"

    # Verificar que el mountpoint está bajo MOUNT_BASE (seguridad)
    real_mount = os.path.realpath(mountpoint)
    real_base = os.path.realpath(MOUNT_BASE)
    if not real_mount.startswith(real_base):
        return False, "Ruta de montaje fuera del directorio permitido"

    # Intentar desmontar
    try:
        result = subprocess.run(
            ["umount", mountpoint],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            # Limpiar directorio vacío
            try:
                os.rmdir(mountpoint)
            except OSError:
                pass

            # Notificar via ntfy
            _ntfy_notify(clean_name, mountpoint)
            return True, f"Dispositivo '{clean_name}' desmontado de {mountpoint}"

        # Fallback: umount forzado
        result = subprocess.run(
            ["umount", "-f", mountpoint],
            capture_output=True, text=True, timeout=10
        )
        if result.returncode == 0:
            try:
                os.rmdir(mountpoint)
            except OSError:
                pass
            _ntfy_notify(clean_name, mountpoint)
            return True, f"Dispositivo '{clean_name}' desmontado (forzado) de {mountpoint}"

        return False, f"Error al desmontar: {result.stderr.strip()}"

    except subprocess.TimeoutExpired:
        return False, "Timeout al intentar desmontar (dispositivo ocupado)"


def _ntfy_notify(device, mountpoint):
    """Enviar notificación de desmontaje via ntfy."""
    try:
        subprocess.run(
            ["curl", "-s", "--max-time", "3",
             "-H", "Title: ⏏️ USB Desmontado (web)",
             "-H", "Tags: usb,eject",
             "-d", f"{device} desmontado de {mountpoint} via USB API",
             f"{NTFY_URL}/usb"],
            capture_output=True, timeout=5
        )
    except (subprocess.TimeoutExpired, FileNotFoundError):
        pass


class USBAPIHandler(BaseHTTPRequestHandler):
    """Handler HTTP para la API de gestión USB."""

    def _send_json(self, status, data):
        """Enviar respuesta JSON."""
        body = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        # CORS para Homepage widgets
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.end_headers()
        self.wfile.write(body)

    def do_OPTIONS(self):
        """CORS preflight."""
        self._send_json(200, {"ok": True})

    def do_GET(self):
        """Handle GET requests."""
        path = urlparse(self.path).path.rstrip("/")

        if path == "/usb/list":
            usbs = get_mounted_usbs()
            self._send_json(200, {
                "count": len(usbs),
                "mount_base": MOUNT_BASE,
                "devices": usbs,
            })
        elif path == "/health":
            self._send_json(200, {
                "status": "ok",
                "service": "usb-api",
                "port": PORT,
                "mount_base": MOUNT_BASE,
            })
        else:
            self._send_json(404, {"error": "Not found"})

    def do_POST(self):
        """Handle POST requests."""
        path = urlparse(self.path).path.rstrip("/")

        # POST /usb/unmount/<device>
        match = re.match(r'^/usb/unmount/([a-zA-Z0-9_-]+)$', path)
        if match:
            device = match.group(1)
            success, message = unmount_device(device)
            status = 200 if success else 400
            self._send_json(status, {
                "success": success,
                "message": message,
                "device": device,
            })
            return

        self._send_json(404, {"error": "Not found"})

    def log_message(self, format, *args):
        """Logging a journald-friendly format."""
        sys.stderr.write(f"[usb-api] {args[0]} {args[1]} {args[2]}\n")


def main():
    """Iniciar servidor HTTP."""
    server = HTTPServer((BIND_ADDR, PORT), USBAPIHandler)
    print(f"[usb-api] Servidor iniciado en {BIND_ADDR}:{PORT}", flush=True)
    print(f"[usb-api] MOUNT_BASE={MOUNT_BASE}", flush=True)
    print(f"[usb-api] NTFY_URL={NTFY_URL}", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\n[usb-api] Detenido.", flush=True)
        server.shutdown()


if __name__ == "__main__":
    main()
PYEOF
    chmod +x /usr/local/lib/usb-api/server.py
    msg_ok "Servidor instalado ✅"

    # ── Paso 4: Crear unit file systemd ───────────────────────
    msg_info "Creando servicio systemd"
    cat > /etc/systemd/system/usb-api.service <<EOF
[Unit]
Description=USB API — REST API para gestión de dispositivos USB
Documentation=https://github.com/ydiaz1699/DebMenux-
After=network.target usb-automount.service
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/bin/python3 /usr/local/lib/usb-api/server.py
Restart=on-failure
RestartSec=5

# Variables de entorno
Environment=USB_API_BIND=0.0.0.0
Environment=USB_API_PORT=${PORT_WEB}
Environment=MOUNT_BASE=${MOUNT_BASE:-/NAS/USB}
Environment=NTFY_URL=http://${server_ip}:8090

# Seguridad (mínimo privilegio + permisos de umount)
User=root
ProtectHome=true
ProtectSystem=strict
ReadWritePaths=/NAS/USB /media /mnt
PrivateTmp=true
NoNewPrivileges=false

# Logging
StandardOutput=journal
StandardError=journal
SyslogIdentifier=usb-api

[Install]
WantedBy=multi-user.target
EOF
    msg_ok "Unit file creado 📄"

    # ── Paso 5: Habilitar e iniciar servicio ──────────────────
    msg_info "Habilitando e iniciando usb-api"
    systemctl daemon-reload
    systemctl enable usb-api.service
    systemctl start usb-api.service
    msg_ok "usb-api activo 🟢"

    # ── Paso 6: Verificar que arrancó ─────────────────────────
    sleep 2
    if systemctl is-active --quiet usb-api.service; then
        msg_ok "Health check OK ✅"
    else
        msg_warn "El servicio arrancó pero puede tardar. Verifica con: systemctl status usb-api"
    fi

    # ── Paso 7: Mostrar info de acceso ────────────────────────
    echo -e ""
    msg_success "${APP} instalado exitosamente! 🔌"
    echo -e "${TAB}${BOLD}🌐 API:${CL}         ${BL}http://${server_ip}:${PORT_WEB}${CL}"
    echo -e "${TAB}${BOLD}📋 Listar:${CL}      curl http://${server_ip}:${PORT_WEB}/usb/list"
    echo -e "${TAB}${BOLD}⏏️  Desmontar:${CL}   curl -X POST http://${server_ip}:${PORT_WEB}/usb/unmount/sdb1"
    echo -e "${TAB}${BOLD}❤️  Health:${CL}      curl http://${server_ip}:${PORT_WEB}/health"
    echo -e ""
    echo -e "${TAB}${DIM}Servicio systemd: usb-api.service${CL}"
    echo -e "${TAB}${DIM}Logs: journalctl -u usb-api -f${CL}"
    echo -e ""

    # ── Registrar en catálogo externo
    register_to_catalog
}

# ==============================================================================
# ACTUALIZACIÓN
# ==============================================================================

update_service() {
    msg_info "Actualizando ${APP}"

    # Re-escribir el script Python (podría tener mejoras)
    install_service

    msg_info "Reiniciando servicio"
    systemctl restart usb-api.service
    msg_ok "${APP} actualizado 🆙"
}

# ==============================================================================
# DESINSTALACIÓN
# ==============================================================================

uninstall_service() {
    msg_info "Deteniendo ${APP}"
    systemctl stop usb-api.service 2>/dev/null || true
    systemctl disable usb-api.service 2>/dev/null || true
    rm -f /etc/systemd/system/usb-api.service
    systemctl daemon-reload
    msg_ok "Servicio systemd eliminado"

    msg_info "Eliminando archivos"
    rm -rf /usr/local/lib/usb-api
    msg_ok "Archivos eliminados"

    echo -e "${TAB}${YWB}⚠️  Los datos/logs permanecen en journald${CL}"
}
