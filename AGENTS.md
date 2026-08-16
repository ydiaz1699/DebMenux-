# AGENTS.md — DebMenux

Toolkit interactivo para instalar y gestionar servicios Docker en Debian/homelab.
Funciona standalone, pero si detecta `nas-dotfiles` registra servicios al catálogo.

## Estructura del proyecto

```
/debmenux/
├── menu                    ← Entry point (debmenu)
├── install.sh              ← Instalador one-liner
├── lib/
│   ├── utils.sh            ← Colores, spinners, msg_info/ok/error
│   ├── docker.sh           ← Helpers Docker (ensure_network, svc_status)
│   ├── integration.sh      ← Registro en catálogo nas-dotfiles (opcional)
│   └── notifications.sh    ← ntfy_send() + wrappers
├── scripts/
│   ├── services/           ← Un .sh por servicio instalable
│   │   ├── _template.sh
│   │   ├── adguard.sh
│   │   ├── emqx.sh
│   │   ├── ntfy.sh
│   │   └── usb-api.sh
│   ├── menus/              ← TUI interactivo
│   └── post-install/       ← USB automount, tuning
├── templates/
│   └── usb-automount/      ← Scripts + config de automontaje
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
- `security_opt: [no-new-privileges:true]` y `cap_drop: [ALL]` obligatorios

## Integración con nas-dotfiles

Si existe `/etc/debmenux/debmenux.conf` o `~/.config/debmenux/debmenux.conf`:

```ini
DOTFILES_DIR=/nas-dotfiles
DOCKER_DIR=/docker
```

Entonces `register_to_catalog()` genera automáticamente:
- `agent/catalog/services/<svc>/ficha.md`
- `agent/catalog/services/<svc>/compose.yml`
- `agent/catalog/services/<svc>/.env.example`
- `docs/services/<svc>-guide.md` (placeholder)
- Notificación ntfy (topic: docker)

## Notificaciones (ntfy)

```bash
source "$DEBMENUX_BASE_DIR/lib/notifications.sh"
ntfy_send "topic" "título" "mensaje" "prioridad" "tags"
# URL configurable via NTFY_URL (default: http://localhost:8090)
```

## USB Automount

- Script: `templates/usb-automount/usb-automount.sh`
- Monta con LABEL del filesystem (o `usb-<dev>` si no tiene)
- Notifica via ntfy al montar/desmontar
- Config: `/etc/usb-automount.conf`

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
