#!/bin/bash
# Inject DietPi first-boot files into an Armbian image
# Usage: ./inject-firstboot.sh <image.img> <board> <distro_target>
set -e

IMG="$1"
BOARD="$2"
DISTRO_TARGET="$3"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

if [[ -z "$IMG" || -z "$BOARD" || -z "$DISTRO_TARGET" ]]; then
    echo "Usage: $0 <image.img> <board> <distro_target>"
    echo "  board: smartpi1 or smartpad"
    echo "  distro_target: 7 (bookworm) or 8 (trixie)"
    exit 1
fi

echo "=== Injecting DietPi first-boot into $IMG ==="
echo "  Board: $BOARD"
echo "  Distro target: $DISTRO_TARGET"

# Setup loop device
echo "Setting up loop device..."
LOOP_DEV=$(sudo losetup -fP --show "$IMG")
echo "  Loop device: $LOOP_DEV"

# Find root partition (p1 or p2)
if [[ -b "${LOOP_DEV}p2" ]]; then
    ROOT_PART="${LOOP_DEV}p2"
else
    ROOT_PART="${LOOP_DEV}p1"
fi
echo "  Root partition: $ROOT_PART"

# Mount
MOUNT_DIR=$(mktemp -d)
sudo mount "$ROOT_PART" "$MOUNT_DIR"

# Mount boot if separate
if [[ -b "${LOOP_DEV}p1" && "$ROOT_PART" != "${LOOP_DEV}p1" ]]; then
    sudo mount "${LOOP_DEV}p1" "$MOUNT_DIR/boot"
fi

echo "  Mounted at: $MOUNT_DIR"

# 1. Copy bootstrap script
echo "Installing dietpi-bootstrap.sh..."
sudo cp "$SCRIPT_DIR/dietpi-bootstrap.sh" "$MOUNT_DIR/usr/local/bin/dietpi-bootstrap.sh"
sudo chmod 755 "$MOUNT_DIR/usr/local/bin/dietpi-bootstrap.sh"

# 2. Create systemd service
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

# 3. Enable the service (create symlink manually since systemctl not available)
echo "Enabling service..."
sudo mkdir -p "$MOUNT_DIR/etc/systemd/system/multi-user.target.wants"
sudo ln -sf /etc/systemd/system/dietpi-bootstrap.service \
    "$MOUNT_DIR/etc/systemd/system/multi-user.target.wants/dietpi-bootstrap.service"

# 4. Create flag file
echo "Creating flag file..."
sudo touch "$MOUNT_DIR/.dietpi-firstboot"

# 5. Write board-specific config
echo "Writing board config..."
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

# 6. SmartPad-specific: inject rotation configs
REPO_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
if [[ "$BOARD" == "smartpad" ]]; then
    echo "Installing SmartPad rotation configs..."

    # Console rotation (fbcon)
    BOOTCFG="$MOUNT_DIR/boot/armbianEnv.txt"
    if [[ -f "$BOOTCFG" ]]; then
        echo "extraargs=fbcon=rotate:2" | sudo tee -a "$BOOTCFG" > /dev/null
        echo "  Console rotation added to armbianEnv.txt"
    fi

    # X11 rotation configs
    sudo mkdir -p "$MOUNT_DIR/etc/X11/xorg.conf.d"
    for conf in "$REPO_DIR/overlay/smartpad/"*.conf; do
        sudo cp -v "$conf" "$MOUNT_DIR/etc/X11/xorg.conf.d/"
    done

    # Rotation script
    sudo cp -v "$REPO_DIR/overlay/smartpad/smartpad-rotate.sh" \
        "$MOUNT_DIR/usr/local/bin/smartpad-rotate.sh"
    sudo chmod 755 "$MOUNT_DIR/usr/local/bin/smartpad-rotate.sh"

    # Autostart for desktop sessions
    sudo mkdir -p "$MOUNT_DIR/etc/xdg/autostart"
    sudo cp -v "$REPO_DIR/overlay/smartpad/smartpad-rotate.desktop" \
        "$MOUNT_DIR/etc/xdg/autostart/"

    # LightDM rotation (if desktop is installed later)
    sudo mkdir -p "$MOUNT_DIR/etc/lightdm/lightdm.conf.d"
    sudo tee "$MOUNT_DIR/etc/lightdm/lightdm.conf.d/50-smartpad-rotate.conf" > /dev/null << 'LIGHTDM'
[Seat:*]
display-setup-script=/usr/local/bin/smartpad-rotate.sh
LIGHTDM

    echo "  SmartPad rotation configs installed"
fi

# Unmount
echo "Unmounting..."
sudo umount "$MOUNT_DIR/boot" 2>/dev/null || true
sudo umount "$MOUNT_DIR"
sudo losetup -d "$LOOP_DEV"
rmdir "$MOUNT_DIR"

echo "=== Injection complete ==="
