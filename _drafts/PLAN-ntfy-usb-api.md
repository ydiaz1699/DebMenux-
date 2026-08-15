# PLAN: ntfy + USB API + Homepage integration

> **Estado:** PENDIENTE — implementar en próxima sesión
> **Fecha:** 2026-08-14
> **Repos involucrados:** DebMenux + nas-dotfiles (ambos)

---

## Contexto

Se quiere agregar:
1. **ntfy** — servidor de notificaciones push (HTTP pub-sub) self-hosted
2. **usb-api** — mini API REST para listar/desmontar USBs desde web
3. **Integración con Homepage** — widgets para ver notificaciones + expulsar USBs
4. **Notificaciones en todas las herramientas** — USB automount, svc, agent, backups

### Requisitos del usuario
- Recibir notificaciones en Android (app ntfy) Y en Windows (browser/PWA)
- Poder desmontar USBs desde Homepage (botón ⏏️) sin ir a la terminal
- Funciona 100% en LAN (sin internet)
- Integrar con AMBOS repos (DebMenux = instalar, nas-dotfiles = operar)

---

## Arquitectura

```
Homepage (:3000)
├── Widget ntfy    → iframe o API de últimas notificaciones
└── Widget USB     → GET /usb/list + botón POST /usb/unmount/:dev

ntfy (:8090)
├── Topics: nas-alerts, usb, docker, backups
├── Recibe de: usb-automount, svc, agent/daemon, cron
└── Push a: Android app + Windows browser (PWA)

usb-api (:8091)
├── GET  /usb/list          → JSON [{device, mountpoint, fs, size}]
├── POST /usb/unmount/:dev  → umount seguro + respuesta + ntfy alert
└── Solo LAN (bind 192.168.1.200, sin auth por ahora)
```

---

## Qué va en cada repo

### DebMenux (`/debmenux`) — INSTALAR + HERRAMIENTAS

| Archivo a crear | Qué hace |
|-----------------|----------|
| `scripts/services/ntfy.sh` | Instala ntfy (compose + .env + server.yml config) |
| `scripts/services/usb-api.sh` | Instala mini API USB (compose con script Python/bash) |
| `lib/notifications.sh` | Función `ntfy_send()` compartida por todos los scripts |
| Actualizar `templates/usb-automount/usb-automount.sh` | Reemplazar `notify-send` → `ntfy_send` via curl |
| Actualizar `services.json` | Agregar ntfy + usb-api al catálogo |

### nas-dotfiles (`/nas-dotfiles`) — OPERAR + INTEGRAR

| Archivo a crear | Qué hace |
|-----------------|----------|
| `agent/catalog/services/ntfy/ficha.md` | Ficha del servicio |
| `agent/catalog/services/ntfy/compose.yml` | Compose final |
| `agent/catalog/services/ntfy/.env.example` | Variables |
| `agent/catalog/services/usb-api/ficha.md` | Ficha del servicio |
| `agent/catalog/services/usb-api/compose.yml` | Compose final |
| `docs/services/ntfy-guide.md` | Guía operativa completa |
| `docker/cli/lib/notifications.sh` | `ntfy_send()` para usar en svc scripts |
| `agent/plugins/notification_plugin.py` | Plugin del agente que envía alertas |
| Actualizar `docker-nas/SKILL.md` | Agregar ntfy a tabla de guías |
| Homepage config (en $dkco/homepage/) | Widgets de ntfy + USB |

---

## Servicios Docker a crear

### ntfy (`$dkco/ntfy/`)

```yaml
services:
  ntfy:
    image: binwiederhier/ntfy:latest
    container_name: ntfy
    restart: unless-stopped
    command: serve
    env_file:
      - ../.env
      - .env
    ports:
      - "8090:80"
    volumes:
      - ./data/cache:/var/cache/ntfy
      - ./data/lib:/var/lib/ntfy
      - ./config:/etc/ntfy
    networks:
      - homepage_net
    deploy:
      resources:
        limits:
          cpus: '0.5'
          memory: 256M
    labels:
      - homepage.group=Sistema
      - homepage.name=ntfy
      - homepage.icon=ntfy
      - homepage.href=http://${SERVER_IP}:8090
      - homepage.description=Notificaciones push del NAS

networks:
  homepage_net:
    external: true
```

Config mínima (`config/server.yml`):
```yaml
base-url: http://192.168.1.200:8090
listen-http: ":80"
cache-file: /var/cache/ntfy/cache.db
auth-default-access: "read-write"
behind-proxy: false
```

### usb-api (`$dkco/usb-api/`)

Opciones de implementación (decidir):
- **Python + Flask** (~50 líneas) — más flexible
- **Bash + socat/netcat** (~30 líneas) — sin dependencias
- **Python + FastAPI** — si se quiere docs automáticas

Recomendación: **Python + Flask** en contenedor ligero:

```yaml
services:
  usb-api:
    image: python:3.11-alpine
    container_name: usb-api
    restart: unless-stopped
    command: python /app/server.py
    ports:
      - "8091:8091"
    volumes:
      - ./app:/app
      - /NAS/USB:/mnt/usb:rshared   # ver USBs montados
    # Necesita acceso al host para umount:
    privileged: true                  # O usar docker socket
    # Alternativa: correr en host network + script nativo (sin Docker)
    networks:
      - homepage_net
    labels:
      - homepage.group=Sistema
      - homepage.name=USB Manager
      - homepage.icon=usb
      - homepage.href=http://${SERVER_IP}:8091
      - homepage.description=Gestión de dispositivos USB

networks:
  homepage_net:
    external: true
```

**⚠️ Decisión pendiente:** Para hacer `umount` real, el contenedor necesita:
- `privileged: true` (funciona pero es inseguro), o
- Montar Docker socket y ejecutar via `docker exec` en el host, o
- **NO usar Docker** — correr como servicio systemd nativo en el host (RECOMENDADO)

**Recomendación:** usb-api como **systemd service nativo** (no Docker):
```
/usr/local/bin/usb-api.py          ← script Python
/etc/systemd/system/usb-api.service ← unit file
```
Así tiene acceso directo a `umount` sin privileged containers.

---

## Función compartida: ntfy_send()

```bash
# Para DebMenux (lib/notifications.sh) y nas-dotfiles (docker/cli/lib/notifications.sh)
ntfy_send() {
    local topic="${1:-nas-alerts}"
    local title="${2:-}"
    local message="${3:-}"
    local priority="${4:-default}"
    local tags="${5:-}"

    local ntfy_url="${NTFY_URL:-http://localhost:8090}"

    local -a headers=()
    [[ -n "$title" ]] && headers+=(-H "Title: $title")
    [[ -n "$priority" ]] && headers+=(-H "Priority: $priority")
    [[ -n "$tags" ]] && headers+=(-H "Tags: $tags")

    curl -s "${headers[@]}" -d "$message" "${ntfy_url}/${topic}" 2>/dev/null || true
}
```

---

## Actualizar usb-automount.sh

Reemplazar todas las llamadas a `notify-send` por `ntfy_send`:

```bash
# Antes (no funciona en headless):
notify-send "🔌 USB Montado" "$device → $mountpoint"

# Después:
ntfy_send "usb" "🔌 USB Montado" "$device ($fs_type) → $mountpoint" "default" "usb,mount"
```

Y en la desconexión insegura:
```bash
ntfy_send "usb" "⚠️ Desconexión Insegura" "$device retirado sin desmontar de $mountpoint. Ejecutar: usb-automount.sh --cleanup" "high" "warning,usb"
```

---

## Homepage widgets

En `$dkco/homepage/config/services.yaml`, agregar:

```yaml
- Sistema:
    - ntfy:
        icon: ntfy
        href: http://192.168.1.200:8090
        description: Notificaciones push
        widget:
          type: customapi
          url: http://ntfy:80/v1/stats
          mappings:
            - field: messages
              label: Mensajes
            - field: topics
              label: Topics

    - USB Manager:
        icon: usb
        href: http://192.168.1.200:8091
        description: Dispositivos USB conectados
        widget:
          type: customapi
          url: http://192.168.1.200:8091/usb/list
          mappings:
            - field: count
              label: USBs montados
```

---

## Orden de implementación sugerido

1. ✅ ntfy servicio (compose + config + .env)
2. ✅ lib/notifications.sh (función ntfy_send)
3. ✅ Actualizar usb-automount.sh (notify-send → ntfy_send)
4. ✅ usb-api (script Python + systemd service)
5. ✅ Homepage widgets (services.yaml)
6. ✅ Fichas en catálogo (ntfy + usb-api)
7. ✅ Guía ntfy-guide.md
8. ✅ Plugin del agente (notification_plugin.py)
9. ✅ Actualizar SKILL.md

---

## Topics ntfy sugeridos

| Topic | Quién envía | Prioridad | Ejemplo |
|-------|-------------|-----------|---------|
| `usb` | usb-automount.sh | default/high | "USB sdb1 montado", "Desconexión insegura" |
| `docker` | svc/agent daemon | high | "emqx DOWN", "update completado" |
| `backups` | cron/svc backup | default | "Backup PostgreSQL OK: 2.3GB" |
| `system` | smart/disk/ssh | urgent | "SMART: disco predice fallo", "SSH login" |
| `nas-alerts` | catch-all | varies | Cualquier alerta general |

---

## Notas para la próxima sesión

- El repo `DebMenux` está en `/debmenux` (git clone directo)
- El repo `nas-dotfiles` está en `/nas-dotfiles`
- Homepage ya corre en `$dkco/homepage` con `homepage_net`
- USB automount ya funciona con MOUNT_BASE="/NAS/USB"
- File Browser usa `:rshared` para ver USBs en tiempo real
- ntfy NO requiere Docker socket — es stateless
- usb-api SÍ necesita acceso al host (recomendado: systemd nativo, no Docker)
- `ntfy_send()` debe existir en AMBOS repos (lib/ de cada uno)
- La SKILL tiene regla de "consultar guía antes de modificar" — actualizar con ntfy



---

## Caso de uso adicional: Alarma + Cámara → ntfy

ntfy soporta **imágenes adjuntas** (header `Attach:` con URL o `-T` con archivo).
Esto permite que Home Assistant envíe snapshots de cámara como push notifications
al browser (Windows) y app (Android) cuando se activa la alarma.

Flujo: HA automation → camera.snapshot → curl -T imagen → ntfy:8090/alarma → push con foto

Detalles completos en: `/nas-dotfiles/_drafts/PLAN-ntfy-usb-api.md` (sección final)

### Implicación para el servicio ntfy

El compose de ntfy necesita suficiente storage para cache de attachments:
- Agregar volumen `./data/attachments:/var/cache/ntfy/attachments`
- Config `server.yml`: `attachment-cache-dir: /var/cache/ntfy/attachments`
- Config `server.yml`: `attachment-total-size-limit: 1G`
- Config `server.yml`: `attachment-file-size-limit: 10M`

### Topic adicional

| Topic | Prioridad | Uso |
|-------|-----------|-----|
| `alarma` | urgent | HA envía snapshot de cámara al detectar movimiento/intrusión |
