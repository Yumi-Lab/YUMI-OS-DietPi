#!/bin/bash
# Verify that first-boot files are correctly injected into an image
# Usage: ./verify-image.sh <image.img> <mode: slim|dietpi> <board>
# Runs on Linux only (requires losetup + ext4 mount)
set -e

IMG="$1"
MODE="$2"
BOARD="$3"
ERRORS=0

if [[ -z "$IMG" || -z "$MODE" || -z "$BOARD" ]]; then
    echo "Usage: $0 <image.img> <mode: slim|dietpi> <board>"
    exit 1
fi

echo "=== Verifying image: $IMG (mode=$MODE, board=$BOARD) ==="

# Mount
LOOP_DEV=$(sudo losetup -fP --show "$IMG")
if [[ -b "${LOOP_DEV}p2" ]]; then
    ROOT_PART="${LOOP_DEV}p2"
else
    ROOT_PART="${LOOP_DEV}p1"
fi
MOUNT_DIR=$(mktemp -d)
sudo mount "$ROOT_PART" "$MOUNT_DIR"
if [[ -b "${LOOP_DEV}p1" && "$ROOT_PART" != "${LOOP_DEV}p1" ]]; then
    sudo mount "${LOOP_DEV}p1" "$MOUNT_DIR/boot" 2>/dev/null || true
fi

check_file() {
    local path="$1"
    local desc="$2"
    if [[ -f "$MOUNT_DIR/$path" ]]; then
        echo "  OK  $desc ($path)"
    else
        echo "  FAIL  $desc ($path)"
        ERRORS=$((ERRORS + 1))
    fi
}

check_symlink() {
    local path="$1"
    local desc="$2"
    if [[ -L "$MOUNT_DIR/$path" ]]; then
        echo "  OK  $desc ($path → $(readlink "$MOUNT_DIR/$path"))"
    else
        echo "  FAIL  $desc ($path)"
        ERRORS=$((ERRORS + 1))
    fi
}

check_executable() {
    local path="$1"
    local desc="$2"
    if [[ -x "$MOUNT_DIR/$path" ]]; then
        echo "  OK  $desc ($path) [executable]"
    else
        echo "  FAIL  $desc ($path) [not executable]"
        ERRORS=$((ERRORS + 1))
    fi
}

# ── Common checks (both modes) ──────────────────────────────────────────────

echo ""
echo "[Common overlay]"
check_file "etc/apt/apt.conf.d/97yumi" "APT no-recommends config"
check_file "etc/sysctl.d/97-yumi.conf" "sysctl tuning"

echo ""
echo "[Armbian neutralisation]"
check_symlink "etc/systemd/system/apt-daily.timer" "apt-daily.timer masked"
check_symlink "etc/systemd/system/apt-daily-upgrade.timer" "apt-daily-upgrade.timer masked"
check_symlink "etc/systemd/system/armbian-first-run.service" "armbian-first-run masked"

# ── Mode-specific checks ────────────────────────────────────────────────────

if [[ "$MODE" == "slim" ]]; then
    echo ""
    echo "[YumiSlim mode]"
    check_executable "usr/local/bin/yumislim-bootstrap.sh" "Bootstrap script"
    check_file "etc/systemd/system/yumislim-bootstrap.service" "Systemd service"
    check_symlink "etc/systemd/system/multi-user.target.wants/yumislim-bootstrap.service" "Service enabled"
    check_file ".yumislim-firstboot" "First-boot flag"
    check_file "boot/yumi-bootstrap.conf" "Board config"

    echo ""
    echo "[Board config content]"
    sudo cat "$MOUNT_DIR/boot/yumi-bootstrap.conf" | sed 's/^/    /'

elif [[ "$MODE" == "dietpi" ]]; then
    echo ""
    echo "[YumiDietPi mode]"
    check_executable "usr/local/bin/dietpi-bootstrap.sh" "Bootstrap script"
    check_file "etc/systemd/system/dietpi-bootstrap.service" "Systemd service"
    check_symlink "etc/systemd/system/multi-user.target.wants/dietpi-bootstrap.service" "Service enabled"
    check_file ".dietpi-firstboot" "First-boot flag"
    check_file "boot/dietpi-bootstrap.conf" "Board config"

    echo ""
    echo "[Board config content]"
    sudo cat "$MOUNT_DIR/boot/dietpi-bootstrap.conf" | sed 's/^/    /'

    if [[ -f "$MOUNT_DIR/boot/dietpi-automation.txt" ]]; then
        echo ""
        echo "[DietPi automation template]"
        echo "  OK  dietpi-automation.txt present"
    fi
fi

# ── SmartPad-specific checks ────────────────────────────────────────────────

if [[ "$BOARD" == "smartpad" ]]; then
    echo ""
    echo "[SmartPad overlay]"
    check_file "etc/X11/xorg.conf.d/02-smartpad-rotate-screen.conf" "X11 screen rotation"
    check_file "etc/X11/xorg.conf.d/03-smartpad-rotate-touch.conf" "X11 touch rotation"
    check_file "etc/X11/xorg.conf.d/04-smartpad-disable-dpms.conf" "X11 DPMS disabled"
    check_executable "usr/local/bin/smartpad-rotate.sh" "Rotation script"
    check_file "etc/xdg/autostart/smartpad-rotate.desktop" "Autostart desktop entry"
    check_file "etc/lightdm/lightdm.conf.d/50-smartpad-rotate.conf" "LightDM rotation"

    if sudo grep -q "fbcon=rotate" "$MOUNT_DIR/boot/armbianEnv.txt" 2>/dev/null; then
        echo "  OK  Console fbcon rotation in armbianEnv.txt"
    else
        echo "  WARN  No fbcon rotation in armbianEnv.txt (may not exist yet)"
    fi
fi

# ── Cleanup ──────────────────────────────────────────────────────────────────

echo ""
sudo umount "$MOUNT_DIR/boot" 2>/dev/null || true
sudo umount "$MOUNT_DIR"
sudo losetup -d "$LOOP_DEV"
rmdir "$MOUNT_DIR"

# ── Result ───────────────────────────────────────────────────────────────────

echo ""
if [[ "$ERRORS" -eq 0 ]]; then
    echo "=== PASSED — All checks OK ==="
    exit 0
else
    echo "=== FAILED — $ERRORS error(s) ==="
    exit 1
fi
