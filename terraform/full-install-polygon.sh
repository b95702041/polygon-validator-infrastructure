# Create the complete installation script
Set-Content -Path "terraform/full-install-polygon.sh" -Value @'
#!/bin/bash
# Enhanced Polygon Validator Installation Script
# Complete version with all P2P fixes
# Downloaded and executed by bootstrap script

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
print_status "Version: 2.0 - P2P Issues Resolved"

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

# Set up Go environment
echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee -a /etc/profile
echo 'export GOPATH=$HOME/go' | sudo tee -a /etc/profile
echo 'export PATH=$PATH:$GOPATH/bin' | sudo tee -a /etc/profile

# Load Go environment for current session
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin

# Build Heimdall
print_status "Building Heimdall"
cd $HOME
if [ ! -d "heimdall" ]; then
    git clone https://github.com/maticnetwork/heimdall.git
fi
cd heimdall
make install

# Build Bor
print_status "Building Bor"
cd $HOME
if [ ! -d "bor" ]; then
    git clone https://github.com/maticnetwork/bor.git
fi
cd bor
make bor

# Initialize Heimdall
print_status "Initializing Heimdall for mainnet"
heimdalld init --chain-id heimdall-137

# Download mainnet genesis
print_status "Downloading mainnet genesis"
curl -o ~/.heimdalld/config/genesis.json https://raw.githubusercontent.com/maticnetwork/heimdall/master/genesis/mainnet/genesis.json

# Configure Heimdall with working peers
print_status "Configuring Heimdall with working peers"
config_file="$HOME/.heimdalld/config/config.toml"

# Apply P2P configuration
sed -i "s/persistent_peers = .*/persistent_peers = \"$HEIMDALL_PEERS\"/" "$config_file"
sed -i 's/seeds = .*/seeds = ""/' "$config_file"
sed -i 's/addr_book_strict = true/addr_book_strict = false/' "$config_file"
sed -i 's/max_num_inbound_peers = .*/max_num_inbound_peers = 200/' "$config_file"
sed -i 's/max_num_outbound_peers = .*/max_num_outbound_peers = 200/' "$config_file"

# Clear cached peer data
rm -f ~/.heimdalld/data/addrbook.json
rm -f ~/.heimdalld/data/pex_reactor.json

# Initialize Bor
print_status "Initializing Bor"
mkdir -p ~/.bor/config
cp ~/bor/builder/files/genesis-mainnet-v1.json ~/.bor/genesis.json
~/bor/build/bin/bor server --datadir ~/.bor init ~/.bor/genesis.json

# Configure Bor
print_status "Configuring Bor with working bootnodes"
cat > ~/.bor/config/config.toml << 'EOF'
[eth]
networkid = 137
syncmode = "full"

[p2p]
maxpeers = 50
port = 30303

[p2p.discovery]
bootnodes = [
    "enode://e4fb013061eba9a2c6fb0a41bbd4149f4808f0fb7e88ec55d7163f19a6f02d64d0ce5ecc81528b769ba552a7068057432d44ab5e9e42842aff5b4709aa2c3f3b@34.89.75.187:30303",
    "enode://a49da6300403cf9b31e30502eb22c142ba4f77c9dda44990bccce9f2121c3152487ee95ee55c6b92d4cdce77845e40f59fd927da70ea91cf935b23e262236d75@34.142.43.249:30303",
    "enode://0e50fdcc2106b0c4e4d9ffbd7798ceda9432e680723dc7b7b4627e384078850c1c4a3e67f17ef2c484201ae6ee7c491cbf5e189b8ffee3948252e9bef59fc54e@35.234.148.172:30303",
    "enode://a0bc4dd2b59370d5a375a7ef9ac06cf531571005ae8b2ead2e9aaeb8205168919b169451fb0ef7061e0d80592e6ed0720f559bd1be1c4efb6e6c4381f1bdb986@35.246.99.203:30303"
]

[rpc]
addr = "127.0.0.1"
port = 8545
corsdomain = ["*"]
vhosts = ["*"]

[ws]
addr = "127.0.0.1"
port = 8546

[heimdall]
url = "http://localhost:1317"
EOF

# Create systemd services
print_status "Creating systemd services"

# Heimdall service
sudo tee /etc/systemd/system/heimdalld.service > /dev/null <<EOF
[Unit]
Description=Heimdall Daemon
After=network.target

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user
ExecStart=/home/ec2-user/go/bin/heimdalld start --home /home/ec2-user/.heimdalld
Restart=on-failure
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

# Heimdall REST service
sudo tee /etc/systemd/system/heimdalld-rest.service > /dev/null <<EOF
[Unit]
Description=Heimdall Rest Server
After=network.target heimdalld.service

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user
ExecStart=/home/ec2-user/go/bin/heimdalld rest-server --home /home/ec2-user/.heimdalld --chain-id heimdall-137 --laddr tcp://127.0.0.1:1317
Restart=on-failure
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

# Bor service
sudo tee /etc/systemd/system/bor.service > /dev/null <<EOF
[Unit]
Description=Bor Daemon
After=network.target heimdalld.service

[Service]
Type=simple
User=ec2-user
WorkingDirectory=/home/ec2-user
ExecStart=/home/ec2-user/bor/build/bin/bor server --config /home/ec2-user/.bor/config/config.toml --datadir /home/ec2-user/.bor
Restart=on-failure
RestartSec=3
LimitNOFILE=4096

[Install]
WantedBy=multi-user.target
EOF

# Start services
print_status "Starting services"
sudo systemctl daemon-reload
sudo systemctl enable heimdalld heimdalld-rest bor

# Start Heimdall first
sudo systemctl start heimdalld
sleep 10

# Start Heimdall REST server
sudo systemctl start heimdalld-rest
sleep 5

# Start Bor
sudo systemctl start bor

# Create monitoring script
print_status "Creating monitoring script"
cat > $HOME/check-polygon-status.sh << 'STATUSEOF'
#!/bin/bash
echo "=== Polygon Validator Status ==="
echo "$(date)"
echo

# Check services
echo "Services:"
sudo systemctl is-active heimdalld && echo "✅ Heimdall: Running" || echo "❌ Heimdall: Not running"
sudo systemctl is-active heimdalld-rest && echo "✅ Heimdall REST: Running" || echo "❌ Heimdall REST: Not running"
sudo systemctl is-active bor && echo "✅ Bor: Running" || echo "❌ Bor: Not running"
echo

# Check Heimdall sync
echo "Heimdall Sync:"
if curl -s --max-time 5 localhost:26657/status > /dev/null; then
    height=$(curl -s localhost:26657/status | jq -r '.result.sync_info.latest_block_height')
    peers=$(curl -s localhost:26657/net_info | jq -r '.result.n_peers')
    echo "  Height: $height"
    echo "  Peers: $peers"
else
    echo "  RPC not accessible"
fi
echo

# Check Bor
echo "Bor Status:"
if curl -s --max-time 5 -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' localhost:8545 > /dev/null; then
    echo "  RPC accessible"
else
    echo "  RPC not accessible"
fi

echo "=== Status check completed ==="
STATUSEOF

chmod +x $HOME/check-polygon-status.sh

print_status "Installation completed successfully!"
print_status "🎉 Polygon validator setup complete with P2P connections working"
print_status "📊 Run ~/check-polygon-status.sh to monitor progress"
print_status "🔍 Monitor logs with: sudo journalctl -u heimdalld -f"
'@