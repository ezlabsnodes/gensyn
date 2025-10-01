#!/usr/bin/env bash
set -Eeuo pipefail
[ "$(id -u)" -eq 0 ] || { echo "Run as root (sudo)."; exit 1; }

SLICE_FILE="/etc/systemd/system/rl-swarm.slice"
SERVICE_FILE="/etc/systemd/system/rl-swarm.service"
REPO_DIR="/root/rl-swarm"

# Slice: limit RAM ~ total-3G, CPUQuota=(cores-1)*100% (min 100)
cores=$(nproc); cpuq=$(( (cores - 1) * 100 )); [ "$cpuq" -lt 100 ] && cpuq=100
total=$(free -g | awk '/^Mem:/{print $2}'); [ -z "${total:-}" ] && total=4
limit=$(( total>3 ? total-3 : 1 ))

cat > "$SLICE_FILE" <<EOF
[Slice]
Description=RL Swarm slice (RAM ${limit}G, CPU ${cpuq}% of ${cores} cores)
MemoryMax=${limit}G
CPUQuota=${cpuq}%
EOF

# Repo + venv bootstrap (ambil zip kamu)
mkdir -p /root
cd /root
rm -rf "$REPO_DIR"
wget -q https://github.com/ezlabsnodes/gensyn/raw/refs/heads/main/test.zip
unzip -o test.zip >/dev/null
rm -f test.zip
chmod +x "$REPO_DIR/run_rl_swarm.sh"
mkdir -p "$REPO_DIR/logs"

# Unit: log ke journal (kompatibel), JANGAN source venv di unit
cat > "$SERVICE_FILE" <<'EOF'
[Unit]
Description=RL Swarm Service
Wants=network-online.target
After=network-online.target

[Service]
Type=simple
Slice=rl-swarm.slice
WorkingDirectory=/root/rl-swarm
ExecStart=/bin/bash -lc '/root/rl-swarm/run_rl_swarm.sh'
StandardOutput=journal
StandardError=journal
LogsDirectory=rl-swarm
Restart=on-failure
RestartSec=10
TimeoutStartSec=600
LimitNOFILE=65535
KillMode=process
# (opsional) paksa CPU-only jika instalasi CUDA berat:
# Environment=CPU_ONLY=1

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable rl-swarm.service
systemctl restart rl-swarm.service

echo "OK. Status:"
systemctl status rl-swarm --no-pager
echo
echo "Follow logs:"
echo "  journalctl -u rl-swarm -f -o cat"
