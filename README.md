# 🐧 DebMenux

**Menu-driven toolkit for Debian Docker homelab/NAS**

An interactive CLI toolkit inspired by [ProxMenux](https://github.com/MacRimi/ProxMenux) and [Proxmox VE Helper-Scripts](https://github.com/community-scripts/ProxmoxVE) — but designed for bare Debian servers running Docker.

Install services with one command, manage containers from a beautiful TUI, and keep your homelab organized.

---

## 📌 Installation

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/ydiaz1699/DebMenux-/main/install.sh)"
```

> ⚠️ Always review scripts before running them: [install.sh](install.sh)

---

## 📌 How to Use

### Interactive Menu (TUI)

```bash
debmenu
```

Then navigate with arrow keys through:
- **Install a Service** — Browse catalog by category, one-click install
- **Manage Services** — Start, stop, restart, view logs
- **Update Services** — Pull latest images and recreate containers
- **System Info** — CPU, RAM, disk, Docker stats at a glance
- **Settings** — Language, Docker directory, updates

### Direct Commands (no TUI)

```bash
# Install a service
debmenu install adguard
debmenu install emqx

# Update a service
debmenu update adguard

# List available services
debmenu list

# Check status of installed services
debmenu status

# Show help
debmenu help
```

---

## 📦 Available Services

| Service | Category | Description |
|---------|----------|-------------|
| **AdGuard Home** | Networking | DNS-level ad/tracker blocker |
| **EMQX** | IoT | High-performance MQTT broker |
| **File Browser** | Storage | Web-based file manager |
| **Portainer CE** | Management | Docker visual management UI |
| **Uptime Kuma** | Monitoring | Self-hosted uptime monitoring |
| **Nginx Proxy Manager** | Networking | Reverse proxy with SSL |
| **ESPHome** | IoT | ESP device firmware builder |
| **Jellyfin** | Media | Free media streaming system |
| **Home Assistant** | IoT | Home automation platform |
| **Vaultwarden** | Security | Bitwarden-compatible passwords |

More services are added regularly. See [services.json](services.json) for the full catalog.

---

## 🏗️ Architecture

```
/usr/local/share/debmenux/      ← Installed location
├── lib/
│   ├── utils.sh                ← Colors, spinners, messages, translations
│   └── docker.sh              ← Docker compose lifecycle helpers
├── scripts/
│   ├── menus/
│   │   ├── main_menu.sh       ← TUI main menu (dialog)
│   │   └── services_menu.sh   ← Category browser + install flow
│   ├── services/               ← One script per service
│   │   ├── _template.sh       ← Template for new services
│   │   ├── adguard.sh
│   │   ├── emqx.sh
│   │   └── ...
│   ├── post-install/           ← Host optimization scripts
│   └── utilities/              ← System utilities
├── lang/                       ← Translation files (es, en)
├── services.json               ← Service catalog
├── config.json                 ← User configuration
└── version.txt
```

---

## 🔧 Dependencies

Installed automatically during setup:

| Package | Purpose |
|---------|---------|
| `dialog` | Interactive terminal menus |
| `curl` | Downloads and connectivity |
| `jq` | JSON processing |
| `git` | Repository cloning and updates |
| `docker` | Container runtime (optional install) |

---

## 🛠️ Creating a New Service Script

1. Copy the template:
   ```bash
   cp scripts/services/_template.sh scripts/services/myservice.sh
   ```

2. Edit the metadata and `install_service()` function

3. Add the entry to `services.json`

4. Test:
   ```bash
   debmenu install myservice
   ```

See [scripts/services/_template.sh](scripts/services/_template.sh) for the full template with inline documentation.

---

## 🌍 Languages

DebMenux supports multiple languages via JSON translation files:

- 🇪🇸 Spanish (default)
- 🇬🇧 English

Change language: `debmenu` → Settings → Change Language

---

## 📋 Requirements

| Component | Details |
|-----------|---------|
| **OS** | Debian 12+ (or derivatives: Ubuntu, Proxmox LXC) |
| **Access** | Root/sudo |
| **Docker** | Installed automatically if missing |
| **Network** | Internet required for install and image pulls |

---

## 🗺️ Roadmap

- [ ] Post-install host optimization (swap, sysctl, zram)
- [ ] Network management (macvlan, bridges, DNS config)
- [ ] Storage management (SMART, mount, fstab)
- [ ] Backup & restore (borg, restic, pg_dump)
- [ ] Web monitor dashboard
- [ ] More service scripts (50+ planned)
- [ ] Auto-update mechanism

---

## 🤝 Contributing

Contributions welcome! To add a new service:

1. Fork the repo
2. Copy `scripts/services/_template.sh` → `scripts/services/yourservice.sh`
3. Add entry to `services.json`
4. Test locally with `debmenu install yourservice`
5. Open a PR

---

## 📄 License

MIT — free to use, modify, and redistribute.

---

## ⭐ Inspired By

- [ProxMenux](https://github.com/MacRimi/ProxMenux) — Menu-driven Proxmox toolkit
- [Proxmox VE Helper-Scripts](https://github.com/community-scripts/ProxmoxVE) — One-command service installs
- [nas-dotfiles](https://github.com/ydiaz1699/nas-dotfiles) — Personal NAS configuration framework
