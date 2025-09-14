#!/bin/bash

# Stop Node
sudo systemctl stop rl-swarm.service
systemctl daemon-reload

# Create directory 'ezlabs'
mkdir -p ezlabs

# Copy files to 'ezlabs'
cp $HOME/rl-swarm/modal-login/temp-data/userApiKey.json $HOME/ezlabs/
cp $HOME/rl-swarm/modal-login/temp-data/userData.json $HOME/ezlabs/
cp $HOME/rl-swarm/swarm.pem $HOME/ezlabs/

cd ~/rl-swarm

# Copy swarm.pem to $HOME/rl-swarm/
cp $HOME/ezlabs/swarm.pem $HOME/rl-swarm/

# Create Screen and run commands
screen -S gensyn -dm bash -c "source .venv/bin/activate && chmod +x run_rl_swarm.sh && ./run_rl_swarm.sh"

echo "Script completed. The 'gensyn' screen session should be running in the background."
echo "Check logs : tail -f $HOME/rl-swarm/logs/swarm_launcher.log"
