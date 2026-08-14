# 🐧 DebMenux

**Toolkit interactivo con menú para homelab Debian + Docker**

Un toolkit CLI interactivo inspirado en [ProxMenux](https://github.com/MacRimi/ProxMenux) y [Proxmox VE Helper-Scripts](https://github.com/community-scripts/ProxmoxVE) — pero diseñado para servidores Debian corriendo Docker.

Instala servicios con un solo comando, gestiona contenedores desde un TUI bonito, y mantén tu homelab organizado.

---

## 📌 Instalación

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ydiaz1699/DebMenux-/main/install.sh)"
```

> ⚠️ Siempre revisa los scripts antes de ejecutarlos: [install.sh](install.sh)

---

## 📌 Cómo Usar

### Menú Interactivo (TUI)

```bash
debmenu
```

Navega con las flechas:
- **📦 Instalar un Servicio** — Explorar catálogo por categoría, instalar con un clic
- **🔧 Gestionar Servicios** — Iniciar, detener, reiniciar, ver logs
- **🆙 Actualizar Servicios** — Descargar imágenes y recrear contenedores
- **📊 Info del Sistema** — CPU, RAM, disco, estadísticas Docker
- **🔩 Configuración** — Idioma, directorio Docker, actualizaciones

### Comandos Directos (sin TUI)

```bash
# Instalar un servicio
debmenu install adguard
debmenu install emqx

# Actualizar un servicio
debmenu update adguard

# Listar servicios disponibles
debmenu list

# Ver estado de servicios instalados
debmenu status

# Mostrar ayuda
debmenu help
```

---

## 📦 Servicios Disponibles

| Servicio | Categoría | Descripción |
|----------|-----------|-------------|
| **AdGuard Home** | 🌐 Red | Bloqueador de anuncios/rastreadores DNS |
| **EMQX** | 🏠 IoT | Broker MQTT de alto rendimiento |
| **File Browser** | 💾 Almacenamiento | Gestor de archivos web |
| **Portainer CE** | 🔧 Gestión | UI visual para Docker |
| **Uptime Kuma** | 📊 Monitoreo | Monitoreo de uptime |
| **Nginx Proxy Manager** | 🌐 Red | Proxy reverso con SSL |
| **ESPHome** | 🏠 IoT | Firmware para dispositivos ESP |
| **Jellyfin** | 🎬 Medios | Sistema de streaming libre |
| **Home Assistant** | 🏠 IoT | Automatización del hogar |
| **Vaultwarden** | 🔒 Seguridad | Gestor de contraseñas |

Se agregan más servicios regularmente. Ver [services.json](services.json) para el catálogo completo.

---

## 🏗️ Arquitectura

```
/usr/local/share/debmenux/       ← Ubicación instalada
├── lib/
│   ├── utils.sh                 ← Colores, spinners, mensajes con emojis
│   ├── docker.sh                ← Helpers de ciclo de vida Docker Compose
│   └── integration.sh           ← Integración con repos externos (opcional)
├── scripts/
│   ├── menus/
│   │   ├── main_menu.sh         ← Menú TUI principal (dialog)
│   │   └── services_menu.sh     ← Explorador de categorías + instalación
│   ├── services/                ← Un script por servicio
│   │   ├── _template.sh         ← Plantilla para nuevos servicios
│   │   ├── adguard.sh
│   │   ├── emqx.sh
│   │   └── ...
│   ├── post-install/            ← Scripts de optimización del host
│   └── utilities/               ← Utilidades del sistema
├── lang/                        ← Archivos de traducción (es, en)
├── services.json                ← Catálogo de servicios
├── config.json                  ← Configuración del usuario
└── version.txt
```

---

## 🔗 Integración con nas-dotfiles

DebMenux puede conectarse opcionalmente con tu repositorio de configuración personal:

```bash
# Activar integración (una sola vez)
mkdir -p ~/.config/debmenux
cp ~/nas-dotfiles/.config/debmenux.conf.example ~/.config/debmenux/debmenux.conf
```

Con la integración habilitada:
- 📋 Cada servicio instalado se registra automáticamente en el catálogo
- 🌐 Las variables globales (SERVER_IP, TZ) se heredan del .env compartido
- 📁 Las rutas se leen de la configuración (sin hardcodear)

---

## 🔧 Dependencias

Se instalan automáticamente durante la configuración:

| Paquete | Propósito |
|---------|-----------|
| `dialog` | Menús interactivos en terminal |
| `curl` | Descargas y conectividad |
| `jq` | Procesamiento JSON |
| `git` | Clonación y actualizaciones |
| `docker` | Runtime de contenedores (instalación opcional) |

---

## 🛠️ Crear un Nuevo Script de Servicio

1. Copiar la plantilla:
   ```bash
   cp scripts/services/_template.sh scripts/services/miservicio.sh
   ```

2. Editar los metadatos y la función `install_service()`

3. Agregar la entrada a `services.json`

4. Probar:
   ```bash
   debmenu install miservicio
   ```

Ver [scripts/services/_template.sh](scripts/services/_template.sh) para la plantilla completa.

---

## 📋 Requisitos

| Componente | Detalles |
|-----------|----------|
| **SO** | Debian 12+ (o derivados: Ubuntu, Proxmox LXC) |
| **Acceso** | Root/sudo |
| **Docker** | Se instala automáticamente si falta |
| **Red** | Internet requerido para instalación y pull de imágenes |

---

## 🗺️ Roadmap

- [ ] Optimización post-instalación del host (swap, sysctl, zram)
- [ ] Gestión de red (macvlan, bridges, DNS)
- [ ] Gestión de almacenamiento (SMART, mount, fstab)
- [ ] Backup y restauración (borg, restic, pg_dump)
- [ ] Dashboard web de monitoreo
- [ ] Más scripts de servicios (50+ planeados)
- [ ] Mecanismo de auto-actualización

---

## 🤝 Contribuir

¡Las contribuciones son bienvenidas! Para agregar un nuevo servicio:

1. Fork del repo
2. Copia `scripts/services/_template.sh` → `scripts/services/tuservicio.sh`
3. Agrega entrada a `services.json`
4. Prueba localmente con `debmenu install tuservicio`
5. Abre un PR

---

## 📄 Licencia

MIT — libre para usar, modificar y redistribuir.

---

## 🔗 Proyectos Relacionados

| Repo | Relación | Descripción |
|------|----------|-------------|
| **[nas-dotfiles](https://github.com/ydiaz1699/nas-dotfiles)** | 🤝 Complementario | Framework de administración personal para NAS con shell, CLI Docker (`svc`), agente IA y catálogo de servicios. Funciona **independiente**, pero puede conectarse opcionalmente con DebMenux. |

### ¿Cómo se relacionan?

```
┌─────────────────────────────────────────────────────────┐
│  DebMenux (este repo)                                   │
│  "Qué servicios existen y cómo instalarlos"             │
│  • Menú TUI interactivo (dialog)                        │
│  • Scripts de instalación por servicio                  │
│  • Post-install: USB automount, Docker, tuning          │
│  • Funciona en CUALQUIER Debian (portable)              │
└───────────────────────┬─────────────────────────────────┘
                        │ Integración OPCIONAL
                        │ (via ~/.config/debmenux/debmenux.conf)
┌───────────────────────▼─────────────────────────────────┐
│  nas-dotfiles (repo independiente)                      │
│  "Cómo está configurado MI servidor"                    │
│  • Shell personalizado (aliases, prompt, nasfk)         │
│  • CLI Docker (svc up/down/logs)                        │
│  • Agente IA (lenguaje natural)                         │
│  • Catálogo de servicios (fichas + guías)               │
│  • Funciona SOLO en tu NAS (personal)                   │
└─────────────────────────────────────────────────────────┘
```

**Cada repo funciona 100% independiente.** La integración es opcional:

- Si `nas-dotfiles` está instalado y configurado (`~/.config/debmenux/debmenux.conf`), DebMenux auto-registra servicios en su catálogo al instalarlos.
- Si NO está instalado, DebMenux funciona perfectamente solo.
- `nas-dotfiles` no depende de DebMenux para nada — tiene su propio CLI (`svc`) y agente.



---

## ⭐ Inspirado Por

- [ProxMenux](https://github.com/MacRimi/ProxMenux) — Toolkit menú-driven para Proxmox
- [Proxmox VE Helper-Scripts](https://github.com/community-scripts/ProxmoxVE) — Instalación de servicios con un comando
