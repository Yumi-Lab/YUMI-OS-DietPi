#!/bin/bash
# YUMI Slim Bootstrap — DietPi-like optimization for Armbian
# Runs once on first boot. Keeps armbian-config (wifi + CPU governor).
# No DietPi installer. Fast (~5 min), minimal network dependency.
set -e

LOG="/var/log/yumislim-bootstrap.log"
exec > >(tee -a "$LOG") 2>&1

echo "============================================"
echo "  YUMI Slim Bootstrap"
echo "  $(date)"
echo "============================================"

# ─── Load board config ──────────────────────────────────────────────────────────

CONF="/boot/yumi-bootstrap.conf"
if [[ -f "$CONF" ]]; then
    echo "Loading config from $CONF"
    # shellcheck source=/dev/null
    source "$CONF"
fi

HOSTNAME="${HOSTNAME:-smartpi}"
TIMEZONE="${TIMEZONE:-Europe/Paris}"
LOCALE="${LOCALE:-C.UTF-8}"

echo "Configuration:"
echo "  BOARD=$BOARD"
echo "  HOSTNAME=$HOSTNAME"
echo "  TIMEZONE=$TIMEZONE"
echo "  LOCALE=$LOCALE"

# ─── Phase 1 : Réseau ──────────────────────────────────────────────────────────

echo ""
echo "[1/7] Waiting for network..."
for i in $(seq 1 60); do
    if curl -sSf --max-time 5 https://deb.debian.org >/dev/null 2>&1; then
        echo "  Network is up."
        break
    fi
    if [[ "$i" -eq 60 ]]; then
        echo "  WARNING: No network after 5 min, continuing offline..."
    fi
    echo "  Attempt $i/60 — waiting 5s..."
    sleep 5
done

# ─── Phase 2 : APT — install essentials ────────────────────────────────────────

echo ""
echo "[2/7] APT update + install essentials..."

# Enforce no-recommends (also injected at build time but belt-and-suspenders)
cat > /etc/apt/apt.conf.d/97yumi << 'EOF'
APT::Install-Recommends "false";
APT::Install-Suggests "false";
Acquire::Languages "none";
DPkg::options "--force-confdef,--force-confold";
EOF

export DEBIAN_FRONTEND=noninteractive
apt-get update -qq

apt-get install -y --no-install-recommends \
    curl wget nano htop \
    cron fake-hwclock \
    tzdata locales \
    ca-certificates \
    systemd-timesyncd

echo "  Essentials installed."

# ─── Phase 3 : Suppression bloat ───────────────────────────────────────────────

echo ""
echo "[3/7] Removing bloat..."

# Docs, man pages, fonts
rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/fonts/* 2>/dev/null || true
rm -rf /usr/share/locale/*/LC_MESSAGES/*.mo 2>/dev/null || true

# Unnecessary packages
apt-get purge -y --auto-remove \
    manpages manpages-dev \
    tasksel tasksel-data \
    2>/dev/null || true

apt-get autoremove -y --purge 2>/dev/null || true
apt-get clean

# APT lists (keep small)
rm -rf /var/lib/apt/lists/*
rm -rf /var/cache/apt/archives/*

# Disable unused services
for svc in apt-daily.timer apt-daily-upgrade.timer \
           apt-daily.service apt-daily-upgrade.service; do
    systemctl disable "$svc" 2>/dev/null || true
    systemctl mask "$svc" 2>/dev/null || true
done
systemctl disable armbian-motd 2>/dev/null || true

echo "  Bloat removed."

# ─── Phase 4 : CPU governor ─────────────────────────────────────────────────────

echo ""
echo "[4/7] Setting CPU governor..."

GOVERNOR="schedutil"
# Fallback chain: schedutil → ondemand → performance
for gov in schedutil ondemand performance; do
    if find /sys/devices/system/cpu/cpu*/cpufreq/scaling_available_governors \
            -exec grep -q "$gov" {} \; 2>/dev/null; then
        GOVERNOR="$gov"
        break
    fi
done

APPLIED=0
for policy in /sys/devices/system/cpu/cpufreq/policy*; do
    if [[ -f "$policy/scaling_governor" ]]; then
        echo "$GOVERNOR" > "$policy/scaling_governor" 2>/dev/null && APPLIED=1 || true
    fi
done
# Fallback per-cpu
for cpu_gov in /sys/devices/system/cpu/cpu*/cpufreq/scaling_governor; do
    [[ -f "$cpu_gov" ]] && echo "$GOVERNOR" > "$cpu_gov" 2>/dev/null && APPLIED=1 || true
done

if [[ "$APPLIED" -eq 1 ]]; then
    echo "  CPU governor set to: $GOVERNOR"
else
    echo "  CPU governor: cpufreq not available (may be set by kernel)"
fi

# Persist for next boots
echo "GOVERNOR=$GOVERNOR" > /etc/default/cpufrequtils 2>/dev/null || true

# Sysctl (also injected at build time, applied now for this session)
sysctl -p /etc/sysctl.d/97-yumi.conf 2>/dev/null || true

# ─── Phase 5 : Hostname / Locale / Timezone ─────────────────────────────────────

echo ""
echo "[5/7] System configuration..."

# Hostname
echo "$HOSTNAME" > /etc/hostname
sed -i "s/127\.0\.1\.1.*/127.0.1.1\t$HOSTNAME/" /etc/hosts 2>/dev/null || \
    echo "127.0.1.1 $HOSTNAME" >> /etc/hosts
hostnamectl set-hostname "$HOSTNAME" 2>/dev/null || true
echo "  Hostname: $HOSTNAME"

# Timezone
timedatectl set-timezone "$TIMEZONE" 2>/dev/null || \
    ln -sf "/usr/share/zoneinfo/$TIMEZONE" /etc/localtime
echo "  Timezone: $TIMEZONE"

# Locale
if ! locale -a 2>/dev/null | grep -qi "${LOCALE%%.*}"; then
    sed -i "s/# *${LOCALE}/${LOCALE}/" /etc/locale.gen 2>/dev/null || \
        echo "${LOCALE} UTF-8" >> /etc/locale.gen
    locale-gen 2>/dev/null || true
fi
update-locale LANG="$LOCALE" 2>/dev/null || true
echo "  Locale: $LOCALE"

# NTP
systemctl enable systemd-timesyncd 2>/dev/null || true
systemctl start systemd-timesyncd 2>/dev/null || true

# ─── Phase 6 : Users ────────────────────────────────────────────────────────────

echo ""
echo "[6/8] Creating user pi..."

# Remove Armbian default users if they exist
for dead_user in armbian dietpi orangepi rock pi64 odroid linaro; do
    if id "$dead_user" &>/dev/null; then
        userdel -r "$dead_user" 2>/dev/null || true
        echo "  Removed user: $dead_user"
    fi
done

# Create user pi with password yumi
if ! id pi &>/dev/null; then
    useradd -m -s /bin/bash -G sudo,audio,video,plugdev,netdev pi
    echo "  Created user: pi"
fi
echo "pi:yumi" | chpasswd
echo "  Password set: pi / yumi"

# Root password
echo "root:yumi" | chpasswd
echo "  Root password set: yumi"

# ─── Phase 7 : SSH ──────────────────────────────────────────────────────────────

echo ""
echo "[7/8] SSH..."
systemctl enable ssh 2>/dev/null || \
    systemctl enable openssh-server 2>/dev/null || true
echo "  SSH enabled."

# ─── Phase 8 : Cleanup ──────────────────────────────────────────────────────────

echo ""
echo "[8/8] Cleanup..."
rm -f /.yumislim-firstboot
systemctl disable yumislim-bootstrap.service 2>/dev/null || true

echo ""
echo "============================================"
echo "  YUMI Slim Bootstrap Complete"
echo "  armbian-config available for:"
echo "    - WiFi setup (armbian-config → Network)"
echo "    - CPU governor (armbian-config → System → CPU)"
echo "  User: pi / Password: yumi (sudo avec mot de passe)"
echo "  Rebooting in 3 seconds..."
echo "============================================"
sleep 3
reboot
