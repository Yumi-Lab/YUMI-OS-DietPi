#!/bin/bash
# Inject first-boot files into an Armbian image
# Usage: ./inject-firstboot.sh <image.img> <board> <distro_target> [--mode slim|dietpi]
set -e

IMG="$1"
BOARD="$2"
DISTRO_TARGET="$3"
MODE="dietpi"

# Parse --mode flag
for arg in "$@"; do
    case "$arg" in
        --mode=*) MODE="${arg#--mode=}" ;;
        --mode) shift; MODE="$1" ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

if [[ -z "$IMG" || -z "$BOARD" || -z "$DISTRO_TARGET" ]]; then
    echo "Usage: $0 <image.img> <board> <distro_target> [--mode slim|dietpi]"
    echo "  board:         smartpi1 or smartpad"
    echo "  distro_target: 7 (bookworm) or 8 (trixie)"
    echo "  mode:          slim (default: dietpi)"
    exit 1
fi

if [[ "$MODE" != "slim" && "$MODE" != "dietpi" ]]; then
    echo "ERROR: --mode must be 'slim' or 'dietpi'"
    exit 1
fi

echo "=== Injecting YUMI first-boot into $IMG ==="
echo "  Board:         $BOARD"
echo "  Distro target: $DISTRO_TARGET"
echo "  Mode:          $MODE"

# ─── Mount helpers ─────────────────────────────────────────────────────────────

mount_image() {
    echo "Setting up loop device..."
    LOOP_DEV=$(sudo losetup -fP --show "$IMG")
    echo "  Loop device: $LOOP_DEV"

    if [[ -b "${LOOP_DEV}p2" ]]; then
        ROOT_PART="${LOOP_DEV}p2"
    else
        ROOT_PART="${LOOP_DEV}p1"
    fi
    echo "  Root partition: $ROOT_PART"

    MOUNT_DIR=$(mktemp -d)
    sudo mount "$ROOT_PART" "$MOUNT_DIR"

    if [[ -b "${LOOP_DEV}p1" && "$ROOT_PART" != "${LOOP_DEV}p1" ]]; then
        sudo mount "${LOOP_DEV}p1" "$MOUNT_DIR/boot"
    fi

    echo "  Mounted at: $MOUNT_DIR"
}

umount_image() {
    echo "Unmounting..."
    sudo umount "$MOUNT_DIR/boot" 2>/dev/null || true
    sudo umount "$MOUNT_DIR"
    sudo losetup -d "$LOOP_DEV"
    rmdir "$MOUNT_DIR"
}

# ─── Common overlay (APT config + sysctl) ──────────────────────────────────────

inject_common_overlay() {
    echo "Injecting common overlay (APT config, sysctl, Armbian neutralisation)..."

    sudo mkdir -p "$MOUNT_DIR/etc/apt/apt.conf.d"
    sudo cp "$REPO_DIR/overlay/common/etc/apt/apt.conf.d/97yumi" \
        "$MOUNT_DIR/etc/apt/apt.conf.d/97yumi"
    sudo chmod 644 "$MOUNT_DIR/etc/apt/apt.conf.d/97yumi"

    sudo mkdir -p "$MOUNT_DIR/etc/sysctl.d"
    sudo cp "$REPO_DIR/overlay/common/etc/sysctl.d/97-yumi.conf" \
        "$MOUNT_DIR/etc/sysctl.d/97-yumi.conf"
    sudo chmod 644 "$MOUNT_DIR/etc/sysctl.d/97-yumi.conf"

    # Mask services at build time (no interactive prompt on first boot)
    sudo mkdir -p "$MOUNT_DIR/etc/systemd/system"
    for unit in apt-daily.timer apt-daily-upgrade.timer \
                armbian-first-run.service armbian-firstrun.service \
                armbian-first-run-gui.service; do
        sudo ln -sf /dev/null "$MOUNT_DIR/etc/systemd/system/$unit" 2>/dev/null || true
    done

    echo "  Common overlay injected"
}

# ─── SmartPad overlay (rotation) ───────────────────────────────────────────────

inject_smartpad_overlay() {
    echo "Installing SmartPad rotation configs..."

    BOOTCFG="$MOUNT_DIR/boot/armbianEnv.txt"
    if [[ -f "$BOOTCFG" ]]; then
        if ! grep -q "fbcon=rotate" "$BOOTCFG"; then
            echo "extraargs=fbcon=rotate:2" | sudo tee -a "$BOOTCFG" > /dev/null
            echo "  Console rotation added to armbianEnv.txt"
        fi
    fi

    sudo mkdir -p "$MOUNT_DIR/etc/X11/xorg.conf.d"
    for conf in "$REPO_DIR/overlay/smartpad/"*.conf; do
        sudo cp -v "$conf" "$MOUNT_DIR/etc/X11/xorg.conf.d/"
    done

    sudo cp -v "$REPO_DIR/overlay/smartpad/smartpad-rotate.sh" \
        "$MOUNT_DIR/usr/local/bin/smartpad-rotate.sh"
    sudo chmod 755 "$MOUNT_DIR/usr/local/bin/smartpad-rotate.sh"

    sudo mkdir -p "$MOUNT_DIR/etc/xdg/autostart"
    sudo cp -v "$REPO_DIR/overlay/smartpad/smartpad-rotate.desktop" \
        "$MOUNT_DIR/etc/xdg/autostart/"

    sudo mkdir -p "$MOUNT_DIR/etc/lightdm/lightdm.conf.d"
    sudo tee "$MOUNT_DIR/etc/lightdm/lightdm.conf.d/50-smartpad-rotate.conf" > /dev/null << 'LIGHTDM'
[Seat:*]
display-setup-script=/usr/local/bin/smartpad-rotate.sh
LIGHTDM

    echo "  SmartPad rotation configs installed"
}

# ─── Mode: slim ────────────────────────────────────────────────────────────────

inject_slim() {
    echo "--- YumiSlim mode ---"

    inject_common_overlay

    # Bootstrap script
    echo "Installing yumislim-bootstrap.sh..."
    sudo cp "$SCRIPT_DIR/yumislim-bootstrap.sh" \
        "$MOUNT_DIR/usr/local/bin/yumislim-bootstrap.sh"
    sudo chmod 755 "$MOUNT_DIR/usr/local/bin/yumislim-bootstrap.sh"

    # Systemd service
    echo "Installing yumislim-bootstrap.service..."
    sudo tee "$MOUNT_DIR/etc/systemd/system/yumislim-bootstrap.service" > /dev/null << 'EOF'
[Unit]
Description=YUMI Slim First-Boot Optimizer
After=network-online.target
Wants=network-online.target
ConditionPathExists=/.yumislim-firstboot

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/yumislim-bootstrap.sh
StandardOutput=journal+console
StandardError=journal+console
TimeoutStartSec=600

[Install]
WantedBy=multi-user.target
EOF
    sudo chmod 644 "$MOUNT_DIR/etc/systemd/system/yumislim-bootstrap.service"

    # Enable service
    sudo mkdir -p "$MOUNT_DIR/etc/systemd/system/multi-user.target.wants"
    sudo ln -sf /etc/systemd/system/yumislim-bootstrap.service \
        "$MOUNT_DIR/etc/systemd/system/multi-user.target.wants/yumislim-bootstrap.service"

    # Flag file
    sudo touch "$MOUNT_DIR/.yumislim-firstboot"

    # Board config
    sudo tee "$MOUNT_DIR/boot/yumi-bootstrap.conf" > /dev/null << CONF
# YUMI Bootstrap Configuration
BOARD="$BOARD"
HW_MODEL=25
DISTRO_TARGET=$DISTRO_TARGET
HOSTNAME=smartpi
TIMEZONE=Europe/Paris
LOCALE=C.UTF-8
CONF
    sudo chmod 644 "$MOUNT_DIR/boot/yumi-bootstrap.conf"

    echo "  YumiSlim injection complete"
}

# ─── Mode: dietpi ──────────────────────────────────────────────────────────────

inject_dietpi() {
    echo "--- YumiDietPi mode ---"

    # Bootstrap script
    echo "Installing dietpi-bootstrap.sh..."
    sudo cp "$SCRIPT_DIR/dietpi-bootstrap.sh" \
        "$MOUNT_DIR/usr/local/bin/dietpi-bootstrap.sh"
    sudo chmod 755 "$MOUNT_DIR/usr/local/bin/dietpi-bootstrap.sh"

    # Systemd service
    echo "Installing dietpi-bootstrap.service..."
    sudo tee "$MOUNT_DIR/etc/systemd/system/dietpi-bootstrap.service" > /dev/null << 'EOF'
[Unit]
Description=YUMI DietPi First-Boot Installer
After=network-online.target
Wants=network-online.target
ConditionPathExists=/.dietpi-firstboot

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/dietpi-bootstrap.sh
StandardOutput=journal+console
StandardError=journal+console
TimeoutStartSec=1800

[Install]
WantedBy=multi-user.target
EOF
    sudo chmod 644 "$MOUNT_DIR/etc/systemd/system/dietpi-bootstrap.service"

    # Enable service
    sudo mkdir -p "$MOUNT_DIR/etc/systemd/system/multi-user.target.wants"
    sudo ln -sf /etc/systemd/system/dietpi-bootstrap.service \
        "$MOUNT_DIR/etc/systemd/system/multi-user.target.wants/dietpi-bootstrap.service"

    # Flag file
    sudo touch "$MOUNT_DIR/.dietpi-firstboot"

    # Board config
    sudo tee "$MOUNT_DIR/boot/dietpi-bootstrap.conf" > /dev/null << CONF
# YUMI DietPi Bootstrap Configuration
BOARD="$BOARD"
HW_MODEL=25
DISTRO_TARGET=$DISTRO_TARGET
WIFI_REQUIRED=1
IMAGE_CREATOR=Yumi
PREIMAGE_INFO=Armbian
GITBRANCH=master
CONF
    sudo chmod 644 "$MOUNT_DIR/boot/dietpi-bootstrap.conf"

    # Copy dietpi.txt automation template from repo
    if [[ -f "$REPO_DIR/dietpi.txt" ]]; then
        echo "Copying dietpi.txt automation template..."
        sudo cp "$REPO_DIR/dietpi.txt" "$MOUNT_DIR/boot/dietpi-automation.txt"
        sudo chmod 644 "$MOUNT_DIR/boot/dietpi-automation.txt"
    fi

    echo "  YumiDietPi injection complete"
}

# ─── Main ──────────────────────────────────────────────────────────────────────

mount_image

if [[ "$MODE" == "slim" ]]; then
    inject_slim
else
    inject_dietpi
fi

if [[ "$BOARD" == "smartpad" ]]; then
    inject_smartpad_overlay
fi

umount_image

echo "=== Injection complete (mode: $MODE) ==="
