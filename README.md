# YUMI-OS-DietPi

Image builder for Yumi SmartPi devices (SmartPi One & SmartPad). Produces two types of images from official [SmartPi-armbian](https://github.com/Yumi-Lab/SmartPi-armbian) server releases.

## Two flavors

| | **YumiSlim** | **YumiDietPi** |
|---|---|---|
| First boot | ~5 min | ~30-45 min |
| Network on first boot | apt update only | Required (downloads DietPi installer) |
| Base system | Armbian + optimizations | Armbian → converted to DietPi |
| WiFi management | `armbian-config` (nmcli) | `dietpi-config` (wpa_supplicant) |
| CPU governor | `armbian-config` + sysctl | `dietpi-set_cpu` |
| DietPi tools | No | Yes (`dietpi-software`, etc.) |
| Approx. image size | ~400 MB | ~300 MB |
| Stability | High (minimal changes) | Medium (full OS conversion) |
| Use case | Yumi custom stack | Full DietPi ecosystem |

**Recommendation:** Start with YumiSlim. Use YumiDietPi only if you need `dietpi-software` or other DietPi-specific tools.

---

## YumiSlim — How it works

1. CI downloads an Armbian server image from the latest SmartPi-armbian release
2. **Build time** — the following are injected into the image:
   - `yumislim-bootstrap.sh` + systemd service
   - APT config: no recommends, no suggests, no language packs
   - sysctl: `vm.swappiness=1`, quiet kernel logging
   - Systemd masks for `apt-daily` timers
   - SmartPad rotation configs (SmartPad only)
3. **First boot** (~5 min):
   - `apt-get update` + install essentials (curl, nano, htop, cron...)
   - Remove bloat: `/usr/share/doc`, `/usr/share/man`, `/usr/share/fonts`
   - Set CPU governor to `schedutil`
   - Configure hostname, timezone, locale
   - `armbian-config` available for WiFi and CPU tuning
   - Reboot

---

## YumiDietPi — How it works

1. CI downloads an Armbian server image
2. **Build time** — injected: `dietpi-bootstrap.sh` + service + `dietpi.txt` automation
3. **First boot** (~30-45 min):
   - Downloads the official [DietPi installer](https://github.com/MichaIng/DietPi)
   - Runs full Armbian → DietPi conversion
   - Applies `dietpi.txt` automation (hostname, locale, timezone, SSH, password)
   - Reboot into DietPi

---

## Supported boards & images

### YumiSlim

| Board | Debian | Image name |
|-------|--------|------------|
| SmartPi One | Bookworm (12) | `Yumi-smartpi1-Slim-bookworm-debian12-server` |
| SmartPi One | Trixie (13) | `Yumi-smartpi1-Slim-trixie-debian13-server` |
| SmartPad | Bookworm (12) | `Yumi-smartpad-Slim-bookworm-debian12-server` |
| SmartPad | Trixie (13) | `Yumi-smartpad-Slim-trixie-debian13-server` |

### YumiDietPi

| Board | Debian | Image name |
|-------|--------|------------|
| SmartPi One | Bookworm (12) | `Yumi-smartpi1-DietPi-bookworm-debian12-server` |
| SmartPi One | Trixie (13) | `Yumi-smartpi1-DietPi-trixie-debian13-server` |
| SmartPad | Bookworm (12) | `Yumi-smartpad-DietPi-bookworm-debian12-server` |
| SmartPad | Trixie (13) | `Yumi-smartpad-DietPi-trixie-debian13-server` |

---

## Default credentials

| | YumiSlim | YumiDietPi |
|---|---|---|
| User | `pi` | `pi` + `dietpi` (DietPi native) |
| Password | `yumi` | `yumi` |
| Root password | `yumi` | `yumi` |
| sudo | mot de passe requis | mot de passe requis |
| Hostname | `smartpi` / `smartpad` | `smartpi` / `smartpad` |

> The Armbian default interactive first-run prompt is disabled — the device boots directly without requiring any keyboard interaction.

---

## Project structure

```
YUMI-OS-DietPi/
├── .github/workflows/
│   ├── BuildImages.yml             # Test builds (push develop / PR / manuel)
│   └── Release.yml                 # GitHub Release publique (manuel + version)
├── src/
│   └── version                     # Version courante
├── configs/
│   ├── smartpi1-bookworm.conf
│   ├── smartpi1-trixie.conf
│   ├── smartpad-bookworm.conf
│   └── smartpad-trixie.conf
├── overlay/
│   ├── common/
│   │   └── etc/
│   │       ├── apt/apt.conf.d/97yumi   # APT: no recommends/suggests
│   │       └── sysctl.d/97-yumi.conf   # sysctl tuning
│   └── smartpad/                        # SmartPad rotation configs
├── scripts/
│   ├── inject-firstboot.sh              # Image injection (supports --mode slim|dietpi)
│   ├── yumislim-bootstrap.sh            # YumiSlim first-boot script
│   └── dietpi-bootstrap.sh              # YumiDietPi first-boot script
├── dietpi.txt                            # DietPi automation template
├── LICENSE
└── README.md
```

---

## Build via GitHub Actions

### Test build (artifacts 30 jours)
**Actions** > **Build Images (Test)** > **Run workflow**
- Choisir flavor : `slim`, `dietpi`, ou `all`
- Se déclenche aussi automatiquement sur push `develop` et PR

### Release publique (GitHub Release permanente)
**Actions** > **Release** > **Run workflow**
- Entrer la version : ex `1.0.0`
- Choisir flavor : `slim`, `dietpi`, ou `all`
- Crée un GitHub Release avec toutes les images + sha256
- Requiert le secret `PAT` (token avec scopes `repo` + `workflow`)

---

## Manual build (local)

```bash
# Download and decompress an Armbian image
wget https://github.com/Yumi-Lab/SmartPi-armbian/releases/latest/download/Yumi-smartpi1-bookworm-server.img.xz
xz -d Yumi-smartpi1-bookworm-server.img.xz

# YumiSlim
sudo ./scripts/inject-firstboot.sh Yumi-smartpi1-bookworm-server.img smartpi1 7 --mode slim

# YumiDietPi
sudo ./scripts/inject-firstboot.sh Yumi-smartpi1-bookworm-server.img smartpi1 7 --mode dietpi

# Flash
sudo dd if=Yumi-smartpi1-bookworm-server.img of=/dev/sdX bs=4M status=progress
```

---

## Monitor first boot

```bash
# YumiSlim
journalctl -u yumislim-bootstrap -f

# YumiDietPi
journalctl -u dietpi-bootstrap -f
```

---

## License

GPL-2.0 — see [LICENSE](LICENSE)
