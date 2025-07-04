#!/bin/bash
# Enhanced Polygon Validator Installation Script
# Complete version with all P2P fixes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Working peers (tested 2025-07-03)
HEIMDALL_PEERS="7f3049e88ac7f820fd86d9120506aaec0dc54b27@34.89.75.187:26656,2d5484feef4257e56ece025633a6ea132d8cadca@35.246.99.203:26656,72a83490309f9f63fdca3a0bef16c290e5cbb09c@35.246.95.65:26656"

# Logging
LOGFILE="/var/log/polygon-install.log"
exec > >(tee -a "$LOGFILE") 2>&1

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_status "Starting Enhanced Polygon Installation"

# Update system
print_status "Updating system packages"
sudo dnf update -y
sudo dnf groupinstall -y "Development Tools"
sudo dnf install -y wget curl git jq nc

# Install Go
print_status "Installing Go 1.24.4"
cd /tmp
wget -q https://go.dev/dl/go1.24.4.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.24.4.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee -a /etc/profile
echo 'export GOPATH=$HOME/go' | sudo tee -a /etc/profile
echo 'export PATH=$PATH:$GOPATH/bin' | sudo tee -a /etc/profile
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin

# Build Heimdall
print_status "Building Heimdall"
cd $HOME
git clone https://github.com/maticnetwork/heimdall.git
cd heimdall
make install

# Build Bor
print_status "Building Bor"
cd $HOME
git clone https://github.com/maticnetwork/bor.git
cd bor
make bor

# Initialize Heimdall
print_status "Initializing Heimdall"
heimdalld init --chain-id heimdall-137
curl -o ~/.heimdalld/config/genesis.json https://raw.githubusercontent.com/maticnetwork/heimdall/master/genesis/mainnet/genesis.json

# Configure Heimdall
print_status "Configuring Heimdall"
sed -i "s/persistent_peers = .*/persistent_peers = \"$HEIMDALL_PEERS\"/" ~/.heimdalld/config/config.toml
sed -i 's/seeds = .*/seeds = ""/' ~/.heimdalld/config/config.toml
sed -i 's/addr_book_strict = true/addr_book_strict = false/' ~/.heimdalld/config/config.toml
sed -i 's/max_num_inbound_peers = .*/max_num_inbound_peers = 200/' ~/.heimdalld/config/config.toml
sed -i 's/max_num_outbound_peers = .*/max_num_outbound_peers = 200/' ~/.heimdalld/config/config.toml
rm -f ~/.heimdalld/data/addrbook.json

print_status "Installation completed successfully!"
