#!/bin/bash
set -Eeuo pipefail

# =========================
# Root check
# =========================
if [ "$(id -u)" -ne 0 ]; then
  echo "This script must be run as root. Please use sudo."
  exit 1
fi

# =========================
# Paths & constants
# =========================
SLICE_FILE="/etc/systemd/system/rl-swarm.slice"
SERVICE_FILE="/etc/systemd/system/rl-swarm.service"
REPO_DIR="/root/rl-swarm"
BACKUP_DIR="/root/ezlabs"
RAM_REDUCTION_GB=3

# =========================
# CPU & RAM limits for slice
# =========================
cpu_cores=$(nproc)
cpu_limit_percentage=$(( (cpu_cores - 1) * 100 ))
if [ "$cpu_limit_percentage" -lt 100 ]; then cpu_limit_percentage=100; fi

total_gb=$(free -g | awk '/^Mem:/ {print $2}')
if [ -z "${total_gb:-}" ] || [ "$total_gb" -le "$RAM_REDUCTION_GB" ]; then
  echo "Not enough RAM to apply slice reduction (total=${total_gb:-0}G)."
  exit 1
fi
limit_gb=$(( total_gb - RAM_REDUCTION_GB ))

# =========================
# Write slice
# =========================
cat > "$SLICE_FILE" <<EOF
[Slice]
Description=Slice for RL Swarm (auto-detected: ${limit_gb}G RAM, ${cpu_limit_percentage}% CPU from ${cpu_cores} cores)
MemoryMax=${limit_gb}G
CPUQuota=${cpu_limit_percentage}%
EOF

# =========================
# Clean old zips (optional)
# =========================
rm -rf officialauto.zip nonofficialauto.zip systemd.zip test.zip \
       original.zip original2.zip ezlabs.zip ezlabs2.zip ezlabs3.zip ezlabs4.zip \
       ezlabs5.zip ezlabs6.zip ezlabs7.zip qwen2-official.zip || true

# =========================
# Ensure unzip
# =========================
if ! command -v unzip >/dev/null 2>&1; then
  apt-get update -y
  apt-get install -y unzip
fi

# =========================
# Preserve credentials safely
# =========================
mkdir -p "$BACKUP_DIR"
if [ -f "$REPO_DIR/modal-login/temp-data/userApiKey.json" ]; then
  cp -f "$REPO_DIR/modal-login/temp-data/userApiKey.json" "$BACKUP_DIR/" || true
fi
if [ -f "$REPO_DIR/modal-login/temp-data/userData.json" ]; then
  cp -f "$REPO_DIR/modal-login/temp-data/userData.json" "$BACKUP_DIR/" || true
fi
if [ -f "$REPO_DIR/swarm.pem" ]; then
  cp -f "$REPO_DIR/swarm.pem" "$BACKUP_DIR/" || true
fi

# =========================
# Stop old service & cleanup
# =========================
systemctl stop rl-swarm.service 2>/dev/null || true
systemctl daemon-reload

# Remove cron line (ignore if no crontab)
( crontab -l 2>/dev/null | grep -v "/root/gensyn_monitoring.sh" ) | crontab - || true

# Close screen session if any
screen -XS gensyn quit 2>/dev/null || true

# Remove old repo
rm -rf "$REPO_DIR"

# =========================
# Download fresh repo
# =========================
cd /root
wget -q https://github.com/ezlabsnodes/gensyn/raw/refs/heads/main/qwen2-official.zip
unzip -o qwen2-official.zip >/dev/null
rm -f qwen2-official.zip

# Ensure repo dir exists
cd "$REPO_DIR"

# Pre-create venv directory (optional)
python3 -m venv "$REPO_DIR/.venv" || true
chmod +x "$REPO_DIR/run_rl_swarm.sh"

# Restore swarm.pem if backed up
if [ -f "$BACKUP_DIR/swarm.pem" ]; then
  cp -f "$BACKUP_DIR/swarm.pem" "$REPO_DIR/" || true
fi

# Make sure local logs dir exists (script may also log there)
mkdir -p "$REPO_DIR/logs"

# =========================
# Create/overwrite service (journal logging)
# =========================
cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=RL Swarm Service
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
Slice=rl-swarm.slice
WorkingDirectory=/root/rl-swarm

# Penting: JANGAN source venv di sini.
# Biarkan run_rl_swarm.sh yang kelola venv (hapus/buat ulang + reinstall deps).
ExecStart=/bin/bash -lc '/root/rl-swarm/run_rl_swarm.sh'

# Buat /var/log/rl-swarm otomatis (bisa dipakai nanti jika ingin file logging)
LogsDirectory=rl-swarm

# Paling kompatibel lintas versi systemd:
StandardOutput=journal
StandardError=journal

Restart=on-failure
RestartSec=10
TimeoutStartSec=600
LimitNOFILE=65535
KillMode=process

[Install]
WantedBy=multi-user.target
EOF

# =========================
# Enable slice & service
# =========================
systemctl daemon-reload
systemctl enable rl-swarm.service
systemctl start rl-swarm.service

echo "Installation completed successfully."
echo "Slice file   : $SLICE_FILE"
echo "Service file : $SERVICE_FILE"
echo "Check status : systemctl status rl-swarm --no-pager"
echo "Follow logs  : journalctl -u rl-swarm -f -o cat"
