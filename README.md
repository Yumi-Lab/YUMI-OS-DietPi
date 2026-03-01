# YUMI-OS-DietPi

DietPi image builder for Yumi SmartPi devices (SmartPi One & SmartPad). Downloads official Armbian server images from [SmartPi-armbian](https://github.com/Yumi-Lab/SmartPi-armbian) releases and converts them to DietPi.

## How it works

This project uses a **first-boot conversion** approach:

1. The CI downloads Armbian server images from the latest SmartPi-armbian release
2. A bootstrap script and systemd service are injected into the image
3. On first boot, the device downloads and runs the official [DietPi installer](https://github.com/MichaIng/DietPi)
4. After conversion and reboot, DietPi is ready to use

**Requirements:** The device needs internet access on first boot for the DietPi conversion (~20-30 min).

## Supported boards

| Board | Debian | DietPi distro_target | Image |
|-------|--------|---------------------|-------|
| SmartPi One | Bookworm (12) | 7 | `Yumi-smartpi1-DietPi-bookworm-debian12-server` |
| SmartPi One | Trixie (13) | 8 | `Yumi-smartpi1-DietPi-trixie-debian13-server` |
| SmartPad | Bookworm (12) | 7 | `Yumi-smartpad-DietPi-bookworm-debian12-server` |
| SmartPad | Trixie (13) | 8 | `Yumi-smartpad-DietPi-trixie-debian13-server` |

## Default credentials

- **User:** `pi` / **Password:** `yumi`
- **Root password:** `yumi` (via DietPi automation)

## Project structure

```
YUMI-OS-DietPi/
├── .github/workflows/
│   └── build-firstboot.yml     # CI workflow
├── configs/
│   ├── smartpi1-bookworm.conf   # SmartPi One + Debian 12
│   ├── smartpi1-trixie.conf     # SmartPi One + Debian 13
│   ├── smartpad-bookworm.conf   # SmartPad + Debian 12
│   └── smartpad-trixie.conf     # SmartPad + Debian 13
├── scripts/
│   ├── dietpi-bootstrap.sh      # First-boot conversion script
│   └── inject-firstboot.sh      # Image injection script (CI)
├── dietpi.txt                   # DietPi config template
├── LICENSE
└── README.md
```

## Usage

### Build images via GitHub Actions

1. Go to **Actions** > **Build DietPi Images (First-Boot)**
2. Click **Run workflow**
3. Optionally specify an Armbian release tag (defaults to latest)
4. Download the built images from the workflow artifacts

### Manual build (local)

```bash
# Download an Armbian server image
wget https://github.com/Yumi-Lab/SmartPi-armbian/releases/latest/download/Yumi-smartpi1-bookworm-debian12-server.img.xz
xz -d Yumi-smartpi1-bookworm-debian12-server.img.xz

# Inject first-boot files
sudo ./scripts/inject-firstboot.sh Yumi-smartpi1-bookworm-debian12-server.img smartpi1 7

# Flash to SD card
sudo dd if=Yumi-smartpi1-bookworm-debian12-server.img of=/dev/sdX bs=4M status=progress
```

### First boot

1. Flash the image to an SD card
2. Connect the device to the network (Ethernet or pre-configured WiFi)
3. Power on — the DietPi conversion starts automatically
4. Wait ~20-30 minutes for the conversion to complete
5. The device reboots into DietPi

Monitor progress: `journalctl -u dietpi-bootstrap -f`

## License

GPL-2.0 — see [LICENSE](LICENSE)
