#!/bin/bash
SLICE_FILE="/etc/systemd/system/rl-swarm.slice"
RAM_REDUCTION_GB=3

if [ "$(id -u)" -ne 0 ]; then
  exit 1
fi

cpu_cores=$(nproc)
cpu_limit_percentage=$(( (cpu_cores - 1) * 100 ))

if [ "$cpu_limit_percentage" -lt 100 ]; then
    cpu_limit_percentage=100
fi

total_gb=$(free -g | awk '/^Mem:/ {print $2}')

if [ "$total_gb" -le "$RAM_REDUCTION_GB" ]; then
  exit 1
fi

limit_gb=$((total_gb - RAM_REDUCTION_GB))

slice_content="[Slice]
Description=Slice for RL Swarm (auto-detected: ${limit_gb}G RAM, ${cpu_limit_percentage}% CPU from ${cpu_cores} cores)
MemoryMax=${limit_gb}G
CPUQuota=${cpu_limit_percentage}%
"

echo -e "$slice_content" | sudo tee "$SLICE_FILE" > /dev/null

rm -rf officialauto.zip nonofficialauto.zip systemd.zip nonofficialauto.zip qwen2-unofficial.zip qwen2-5-1-5-b.zip test.zip

sudo apt-get install -y unzip

# Create directory 'ezlabs'
mkdir -p ezlabs

# Copy files to 'ezlabs'
cp $HOME/rl-swarm/modal-login/temp-data/userApiKey.json $HOME/ezlabs/
cp $HOME/rl-swarm/modal-login/temp-data/userData.json $HOME/ezlabs/
cp $HOME/rl-swarm/swarm.pem $HOME/ezlabs/

# Close Screen and Remove Old Repository
sudo systemctl stop rl-swarm.service
systemctl daemon-reload
crontab -l | grep -v "/root/gensyn_monitoring.sh" | crontab -
screen -XS gensyn quit
cd ~
rm -rf rl-swarm

# Download and Unzip ezlabs7.zip, then change to rl-swarm directory
wget https://github.com/ezlabsnodes/gensyn/raw/refs/heads/main/test.zip && \
unzip test.zip && \
cd ~/rl-swarm
python3 -m venv /root/rl-swarm/.venv
chmod +x /root/rl-swarm/run_rl_swarm.sh

# Copy swarm.pem to $HOME/rl-swarm/
cp $HOME/ezlabs/swarm.pem $HOME/rl-swarm/

# Define service file path
SERVICE_FILE="/etc/systemd/system/rl-swarm.service"

# Create or overwrite the service file
cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Gensyn RL Swarm Service
# Memastikan layanan dimulai setelah jaringan siap dan waktu sistem sinkron
After=network-online.target time-sync.target
Wants=network-online.target

[Service]
# Menentukan pengguna yang menjalankan layanan, penting untuk keamanan dan perizinan
User=root
Group=root

# Direktori kerja, sudah benar
WorkingDirectory=/root/rl-swarm

# Cara yang lebih bersih untuk menggunakan virtual environment python
# Systemd akan menambahkan path venv di awal $PATH
Environment="PATH=/root/rl-swarm/.venv/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Langsung menjalankan skrip. Tidak perlu 'bash -c' karena PATH sudah diatur
ExecStart=/root/rl-swarm/run_rl_swarm.sh

# Type=simple adalah default dan yang paling cocok untuk skrip ini
# Tidak perlu ditulis secara eksplisit, tapi dicantumkan di sini untuk kejelasan
Type=simple

# Opsi restart, sudah benar
Restart=always
RestartSec=30

# Atur batas waktu yang wajar untuk startup awal skrip
TimeoutStartSec=600

# Mengarahkan semua output (stdout/stderr) ke systemd journal
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Check if file was created successfully
if [ -f "$SERVICE_FILE" ]; then
    echo "Service file created/updated successfully at $SERVICE_FILE"
    
    # Reload systemd daemon
    systemctl daemon-reload
    echo "Systemd daemon reloaded."
    
    # Enable the service
    systemctl enable rl-swarm.service
    sudo systemctl start rl-swarm.service  
    echo "Installation completed successfully."
    echo "Check Logs: journalctl -u rl-swarm -f -o cat"
else
    echo "Failed to create service file."
    exit 1
fi
