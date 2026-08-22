# AGENTS.md — DebMenux

Toolkit interactivo para instalar y gestionar servicios Docker en Debian/homelab.
Funciona standalone, pero si detecta `nas-dotfiles` registra servicios al catálogo.

## Estructura del proyecto

```
/debmenux/
├── menu                    ← Entry point (debmenu)
├── install.sh              ← Instalador one-liner
├── AGENTS.md               ← Este archivo (contexto para AI agents)
├── lib/
│   ├── utils.sh            ← Colores, spinners, msg_info/ok/error
│   ├── docker.sh           ← Helpers Docker (ensure_network, svc_status)
│   ├── integration.sh      ← Registro en catálogo + guía + ntfy (cascada)
│   └── notifications.sh    ← ntfy_send() + wrappers (usb, docker, backup)
├── scripts/
│   ├── services/           ← Un .sh por servicio instalable
│   │   ├── _template.sh
│   │   ├── adguard.sh
│   │   ├── emqx.sh
│   │   ├── iobroker.sh
│   │   ├── flowise.sh
│   │   ├── ntfy.sh         ← Servidor notificaciones push (Docker, :8090)
│   │   └── usb-api.sh      ← API REST USBs (systemd nativo, :8091)
│   ├── menus/              ← TUI interactivo
│   └── post-install/       ← USB automount, tuning
├── templates/
│   └── usb-automount/      ← Scripts + config (monta con LABEL)
├── services.json           ← Catálogo de servicios disponibles
├── lang/                   ← i18n (es.json, en.json)
└── version.txt
```

## Comandos

```bash
debmenu                    # Menú TUI interactivo
debmenu install <svc>      # Instalar servicio directamente
debmenu update <svc>       # Actualizar servicio
debmenu list               # Listar servicios disponibles
debmenu status             # Estado de servicios instalados
```

## Crear un script de servicio nuevo

1. Copiar `scripts/services/_template.sh`
2. Renombrar a `scripts/services/<service_id>.sh`
3. Llenar: `APP`, `APP_ID`, `CATEGORY`, `IMAGE`, `PORT_WEB`
4. Implementar `install_service()` siguiendo el orden:
   - mkdir → archivos → permisos → levantar
5. Agregar entrada en `services.json`
6. Al final de `install_service()`, llamar `register_to_catalog`

## Convenciones de código

- Bash puro (sin dependencias externas excepto Docker, curl, jq)
- `msg_info/msg_ok/msg_error/msg_warn` para output (con spinner)
- `ensure_package` para deps del sistema
- `ensure_network` para redes Docker
- `secure_env` para permisos de .env (chmod 600)
- `generate_password` para secretos aleatorios
- El compose se llama `compose.yml` (nunca docker-compose.yml)
- Puertos en rango 8000-8999 para apps web
- `security_opt: [no-new-privileges:true]` obligatorio
- `cap_drop: [ALL]` por defecto; servicios que instalan adapters o dependencias en runtime pueden omitirlo si la excepción queda documentada (ioBroker y Node-RED)

## Integración con nas-dotfiles

Si existe `/etc/debmenux/debmenux.conf` o `~/.config/debmenux/debmenux.conf`:

```ini
DOTFILES_DIR=/nas-dotfiles
DOCKER_DIR=/docker
```

Entonces `register_to_catalog()` genera automáticamente en cascada:
- `agent/catalog/services/<svc>/ficha.md` — metadatos del servicio
- `agent/catalog/services/<svc>/compose.yml` — copia del compose
- `agent/catalog/services/<svc>/.env.example` — secretos sanitizados (__pega_aqui__)
- `docs/services/<svc>-guide.md` — guía placeholder (completar manualmente)
- Notificación ntfy (topic: docker) — "Servicio X registrado"

**Pipeline inverso:** `svc catalog-sync` en nas-dotfiles también genera
scripts placeholder en `/debmenux/scripts/services/` si no existen.

## Notificaciones (ntfy)

```bash
source "$DEBMENUX_BASE_DIR/lib/notifications.sh"
ntfy_send "topic" "título" "mensaje" "prioridad" "tags"
# URL configurable via NTFY_URL (default: http://localhost:8090)
```

## USB Automount

- Script: `templates/usb-automount/usb-automount.sh`
- Monta con **LABEL** del filesystem (ej: `/NAS/USB/MI_PENDRIVE`)
- Fallback si no hay label: `/NAS/USB/usb-<dev>` (ej: `usb-sdb1`)
- Notifica via ntfy al montar/desmontar/desconexión insegura
- Config: `/etc/usb-automount.conf` (ENABLE_NOTIFICATIONS, NTFY_URL, MOUNT_BASE)
- Cleanup: `usb-automount.sh --cleanup` (o timer automático cada hora)
- Mountpoint fantasma (device desconectado bruscamente): `umount -l <path> && rmdir <path>`

## Testing

```bash
# Verificar sintaxis
bash -n scripts/services/mi-servicio.sh

# Verificar que services.json es válido
python3 -c "import json; json.load(open('services.json'))"
```

## Reglas estrictas

- NUNCA crear archivos fuera de `$DOCKER_DIR/<svc>/`
- NUNCA exponer puertos de bases de datos al host
- SIEMPRE llamar `register_to_catalog` al final de install
- SIEMPRE agregar healthcheck en el compose
- SIEMPRE usar labels `homepage.*` para Homepage (auto-descubrimiento)
- Orden de ejecución: mkdir → archivos → permisos → levantar
