#!/bin/bash
# YUMI DietPi Bootstrap
# Runs once on first boot to convert Armbian to DietPi.
# Downloads the official DietPi installer and runs it on real hardware.
set -e

LOG="/var/log/dietpi-bootstrap.log"
exec > >(tee -a "$LOG") 2>&1

echo "============================================"
echo "  YUMI DietPi Bootstrap"
echo "  $(date)"
echo "============================================"

# ─── Load board config ──────────────────────────────────────────────────────────

CONF="/boot/dietpi-bootstrap.conf"
if [[ -f "$CONF" ]]; then
    echo "Loading config from $CONF"
    # shellcheck source=/dev/null
    source "$CONF"
fi

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

# ─── Wait for network ───────────────────────────────────────────────────────────

echo ""
echo "Waiting for network connectivity..."
for i in $(seq 1 60); do
    if curl -sSf --max-time 5 https://raw.githubusercontent.com >/dev/null 2>&1; then
        echo "Network is up."
        break
    fi
    if [[ "$i" -eq 60 ]]; then
        echo "ERROR: No network after 5 min. Cannot download DietPi installer."
        exit 1
    fi
    echo "  Attempt $i/60 — waiting..."
    sleep 5
done

# ─── Download + run DietPi installer ────────────────────────────────────────────

echo ""
echo "Downloading DietPi installer..."
curl -sSf https://raw.githubusercontent.com/MichaIng/DietPi/master/.build/images/dietpi-installer \
    -o /tmp/dietpi-installer
chmod +x /tmp/dietpi-installer

echo "Running DietPi installer..."
/tmp/dietpi-installer

# ─── Post-install: apply dietpi.txt automation ──────────────────────────────────

echo ""
echo "Configuring DietPi automation..."

DIETPI_TXT="/boot/dietpi.txt"
AUTOMATION_SRC="/boot/dietpi-automation.txt"

if [[ -f "$DIETPI_TXT" ]]; then
    if [[ -f "$AUTOMATION_SRC" ]]; then
        # Apply values from our automation template over the installed dietpi.txt
        echo "Applying automation template from $AUTOMATION_SRC..."
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ "$key" =~ ^[[:space:]]*# ]] && continue
            [[ -z "$key" ]] && continue
            key="${key// /}"
            if grep -q "^${key}=" "$DIETPI_TXT"; then
                sed -i "s|^${key}=.*|${key}=${value}|" "$DIETPI_TXT"
            fi
        done < <(grep -v '^[[:space:]]*#' "$AUTOMATION_SRC" | grep '=')
        echo "  Automation template applied."
    else
        # Fallback: apply inline settings
        sed -i 's/^AUTO_SETUP_AUTOMATED=.*/AUTO_SETUP_AUTOMATED=1/' "$DIETPI_TXT"
        sed -i 's/^AUTO_SETUP_GLOBAL_PASSWORD=.*/AUTO_SETUP_GLOBAL_PASSWORD=yumi/' "$DIETPI_TXT"
        sed -i 's/^AUTO_SETUP_ACCEPT_LICENSE=.*/AUTO_SETUP_ACCEPT_LICENSE=1/' "$DIETPI_TXT"
        sed -i 's/^AUTO_SETUP_LOCALE=.*/AUTO_SETUP_LOCALE=C.UTF-8/' "$DIETPI_TXT"
        sed -i 's/^AUTO_SETUP_TIMEZONE=.*/AUTO_SETUP_TIMEZONE=Europe\/Paris/' "$DIETPI_TXT"
        sed -i 's/^AUTO_SETUP_SSH_SERVER_INDEX=.*/AUTO_SETUP_SSH_SERVER_INDEX=-2/' "$DIETPI_TXT"
        sed -i 's/^AUTO_SETUP_NET_HOSTNAME=.*/AUTO_SETUP_NET_HOSTNAME=smartpi/' "$DIETPI_TXT"
    fi
fi

# ─── SmartPad: hostname from board config ───────────────────────────────────────

if [[ "${BOARD:-}" == "smartpad" ]]; then
    if [[ -f "$DIETPI_TXT" ]]; then
        sed -i 's/^AUTO_SETUP_NET_HOSTNAME=.*/AUTO_SETUP_NET_HOSTNAME=smartpad/' "$DIETPI_TXT"
    fi
fi

# ─── Create user pi:yumi ────────────────────────────────────────────────────────

echo ""
echo "Creating user pi..."
if ! id pi &>/dev/null; then
    useradd -m -s /bin/bash -G sudo pi
fi
echo "pi:yumi" | chpasswd
echo "root:yumi" | chpasswd
echo "  User pi created (password: yumi)"

# ─── Cleanup ────────────────────────────────────────────────────────────────────

echo ""
echo "Cleaning up bootstrap..."
rm -f /.dietpi-firstboot
rm -f /tmp/dietpi-installer
systemctl disable dietpi-bootstrap.service 2>/dev/null || true

echo ""
echo "============================================"
echo "  DietPi Bootstrap Complete"
echo "  Rebooting in 5 seconds..."
echo "============================================"
sleep 5
reboot
