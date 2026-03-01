#!/bin/bash
# YUMI DietPi First-Boot Installer
# This script runs once on first boot to convert Armbian to DietPi.
# It downloads the official DietPi installer and runs it on real hardware.
set -e

LOG="/var/log/dietpi-bootstrap.log"
exec > >(tee -a "$LOG") 2>&1

echo "============================================"
echo "  YUMI DietPi Bootstrap"
echo "  $(date)"
echo "============================================"

# Read board-specific config if available
CONF="/boot/dietpi-bootstrap.conf"
if [[ -f "$CONF" ]]; then
    echo "Loading config from $CONF"
    source "$CONF"
fi

# DietPi installer environment variables
export GITBRANCH="${GITBRANCH:-master}"
export IMAGE_CREATOR="${IMAGE_CREATOR:-Yumi}"
export PREIMAGE_INFO="${PREIMAGE_INFO:-Armbian}"
export HW_MODEL="${HW_MODEL:-25}"
export WIFI_REQUIRED="${WIFI_REQUIRED:-1}"
export DISTRO_TARGET="${DISTRO_TARGET:-7}"

echo "Configuration:"
echo "  HW_MODEL=$HW_MODEL"
echo "  DISTRO_TARGET=$DISTRO_TARGET"
echo "  WIFI_REQUIRED=$WIFI_REQUIRED"

# Wait for network
echo "Waiting for network connectivity..."
for i in $(seq 1 60); do
    if curl -sSf --max-time 5 https://raw.githubusercontent.com >/dev/null 2>&1; then
        echo "Network is up."
        break
    fi
    echo "  Attempt $i/60 - waiting..."
    sleep 5
done

# Download official DietPi installer
echo "Downloading DietPi installer..."
curl -sSf https://raw.githubusercontent.com/MichaIng/DietPi/master/.build/images/dietpi-installer -o /tmp/dietpi-installer
chmod +x /tmp/dietpi-installer

# Run DietPi installer
echo "Running DietPi installer..."
/tmp/dietpi-installer

# Post-install: configure dietpi.txt for automated first DietPi boot
echo "Configuring DietPi automation..."
if [[ -f /boot/dietpi.txt ]]; then
    # Set automated mode
    sed -i 's/^AUTO_SETUP_AUTOMATED=.*/AUTO_SETUP_AUTOMATED=1/' /boot/dietpi.txt
    sed -i 's/^AUTO_SETUP_GLOBAL_PASSWORD=.*/AUTO_SETUP_GLOBAL_PASSWORD=yumi/' /boot/dietpi.txt
    sed -i 's/^AUTO_SETUP_ACCEPT_LICENSE=.*/AUTO_SETUP_ACCEPT_LICENSE=1/' /boot/dietpi.txt
    sed -i 's/^AUTO_SETUP_LOCALE=.*/AUTO_SETUP_LOCALE=C.UTF-8/' /boot/dietpi.txt
    sed -i 's/^AUTO_SETUP_TIMEZONE=.*/AUTO_SETUP_TIMEZONE=Europe\/Paris/' /boot/dietpi.txt
    sed -i 's/^AUTO_SETUP_SSH_SERVER_INDEX=.*/AUTO_SETUP_SSH_SERVER_INDEX=-2/' /boot/dietpi.txt
    sed -i 's/^AUTO_SETUP_NET_HOSTNAME=.*/AUTO_SETUP_NET_HOSTNAME=smartpi/' /boot/dietpi.txt
fi

# Create user pi with password yumi
echo "Creating user pi..."
if ! id pi &>/dev/null; then
    useradd -m -s /bin/bash -G sudo pi
fi
echo "pi:yumi" | chpasswd

# Cleanup bootstrap
echo "Cleaning up bootstrap..."
rm -f /.dietpi-firstboot
rm -f /tmp/dietpi-installer
systemctl disable dietpi-bootstrap.service 2>/dev/null || true

echo "============================================"
echo "  DietPi Bootstrap Complete"
echo "  Rebooting in 5 seconds..."
echo "============================================"
sleep 5
reboot
