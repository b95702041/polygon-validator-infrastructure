#!/bin/bash
# Enhanced Polygon Validator Installation Script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Log function
log() {
    echo "$(date): $1" >> /var/log/polygon-bootstrap.log
}

print_status "Starting Enhanced Polygon Installation"
log "Starting Enhanced Polygon Installation"

# Update system with conflict resolution
print_status "Updating system packages"
sudo dnf update -y --allowerasing
sudo dnf groupinstall -y --allowerasing "Development Tools"
sudo dnf install -y --allowerasing wget curl git jq nc

# Install Go
print_status "Installing Go 1.24.4"
cd /tmp
if [ ! -f "go1.24.4.linux-amd64.tar.gz" ]; then
    wget -q https://go.dev/dl/go1.24.4.linux-amd64.tar.gz
fi
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.24.4.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee -a /etc/profile
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin

print_status "System update completed"
log "System update completed"

# Install Polygon Edge
print_status "Installing Polygon Edge"
log "Installing Polygon Edge"

# Create polygon user first
print_status "Creating polygon user"
sudo useradd -r -s /bin/false polygon 2>/dev/null || true

# Create directories
print_status "Creating directories"
sudo mkdir -p /opt/polygon
sudo mkdir -p /var/lib/polygon
sudo mkdir -p /var/log/polygon
sudo mkdir -p /etc/polygon

# Build Polygon Edge from source (more reliable than binary download)
print_status "Building Polygon Edge from source"
cd /tmp
if [ ! -d "polygon-edge" ]; then
    git clone https://github.com/0xPolygon/polygon-edge.git
fi
cd polygon-edge

# Checkout a stable version
git checkout develop

# Build the binary
print_status "Compiling Polygon Edge binary"
go build -o polygon-edge main.go

# Install the binary
print_status "Installing Polygon Edge binary"
sudo cp polygon-edge /usr/local/bin/
sudo chmod +x /usr/local/bin/polygon-edge

# Verify installation
print_status "Verifying Polygon Edge installation"
if /usr/local/bin/polygon-edge version; then
    print_status "✅ Polygon Edge installed successfully"
else
    print_error "❌ Polygon Edge installation failed"
    exit 1
fi

# Set ownership
print_status "Setting up permissions"
sudo chown -R polygon:polygon /opt/polygon
sudo chown -R polygon:polygon /var/lib/polygon
sudo chown -R polygon:polygon /var/log/polygon
sudo chown -R polygon:polygon /etc/polygon

# Initialize secrets
print_status "Initializing node secrets"
sudo -u polygon /usr/local/bin/polygon-edge secrets init --data-dir /var/lib/polygon

# Create genesis file
print_status "Creating genesis configuration"
sudo -u polygon /usr/local/bin/polygon-edge genesis \
    --dir /var/lib/polygon \
    --name "polygon-testnet" \
    --pos \
    --epoch-size 10 \
    --premine=0x85da99c8a7C2C95964c8EfD687E95E632Fc533D6:1000000000000000000000 \
    --premine=0x228466F2C715CbEC05dEAbfAc040ce3619d7CF0B:1000000000000000000000

# Create configuration file
print_status "Creating configuration file"
sudo tee /etc/polygon/config.yaml > /dev/null <<EOF
chain_config: /var/lib/polygon/genesis.json
secrets_config:
  type: local
  dir: /var/lib/polygon
network:
  libp2p_addr: 0.0.0.0:1478
  nat_addr: 
  dns_addr: 
  max_peers: 40
  max_outbound_peers: 8
  max_inbound_peers: 32
seal: true
tx_pool:
  price_limit: 1
  max_slots: 4096
  max_account_enqueued: 128
log_level: INFO
restore_file: ""
block_gas_target: 0x0
grpc_addr: 0.0.0.0:9632
jsonrpc_addr: 0.0.0.0:8545
telemetry:
  prometheus_addr: 0.0.0.0:5001
relayer: false
num_block_confirmations: 64
EOF

sudo chown polygon:polygon /etc/polygon/config.yaml

# Create systemd service
print_status "Creating systemd service"
sudo tee /etc/systemd/system/polygon-edge.service > /dev/null <<EOF
[Unit]
Description=Polygon Edge Node
After=network.target
Wants=network.target

[Service]
Type=simple
User=polygon
Group=polygon
ExecStart=/usr/local/bin/polygon-edge server --config /etc/polygon/config.yaml
Restart=always
RestartSec=10
StandardOutput=append:/var/log/polygon/polygon-edge.log
StandardError=append:/var/log/polygon/polygon-edge-error.log
SyslogIdentifier=polygon-edge
KillSignal=SIGTERM
TimeoutStopSec=30

[Install]
WantedBy=multi-user.target
EOF

# Create log rotation
print_status "Setting up log rotation"
sudo tee /etc/logrotate.d/polygon-edge > /dev/null <<EOF
/var/log/polygon/*.log {
    daily
    missingok
    rotate 52
    compress
    delaycompress
    notifempty
    create 640 polygon polygon
    postrotate
        systemctl reload polygon-edge
    endscript
}
EOF

# Create monitoring and utility scripts
print_status "Creating utility scripts"

# Status script
sudo tee /usr/local/bin/polygon-status > /dev/null <<EOF
#!/bin/bash
echo "=== Polygon Edge Status ==="
systemctl status polygon-edge --no-pager
echo ""
echo "=== Latest Logs ==="
tail -n 20 /var/log/polygon/polygon-edge.log
echo ""
echo "=== Node Info ==="
curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    http://localhost:8545 | jq . 2>/dev/null || echo "RPC not ready"
echo ""
echo "=== Peers ==="
curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
    http://localhost:8545 | jq . 2>/dev/null || echo "RPC not ready"
EOF

# Logs script
sudo tee /usr/local/bin/polygon-logs > /dev/null <<EOF
#!/bin/bash
if [ "\$1" = "follow" ] || [ "\$1" = "-f" ]; then
    tail -f /var/log/polygon/polygon-edge.log
else
    tail -n 100 /var/log/polygon/polygon-edge.log
fi
EOF

# Restart script
sudo tee /usr/local/bin/polygon-restart > /dev/null <<EOF
#!/bin/bash
echo "Restarting Polygon Edge service..."
sudo systemctl restart polygon-edge
echo "Waiting for service to start..."
sleep 5
sudo systemctl status polygon-edge --no-pager
EOF

# Make scripts executable
sudo chmod +x /usr/local/bin/polygon-status
sudo chmod +x /usr/local/bin/polygon-logs
sudo chmod +x /usr/local/bin/polygon-restart

# Create firewall rules (if firewalld is running)
if systemctl is-active --quiet firewalld; then
    print_status "Configuring firewall"
    sudo firewall-cmd --permanent --add-port=8545/tcp  # JSON-RPC
    sudo firewall-cmd --permanent --add-port=9632/tcp  # GRPC
    sudo firewall-cmd --permanent --add-port=1478/tcp  # LibP2P
    sudo firewall-cmd --permanent --add-port=5001/tcp  # Prometheus
    sudo firewall-cmd --reload
fi

# Enable and start the service
print_status "Enabling and starting Polygon Edge service"
sudo systemctl daemon-reload
sudo systemctl enable polygon-edge
sudo systemctl start polygon-edge

# Wait for service to start
print_status "Waiting for Polygon Edge to start..."
sleep 30

# Check service status
print_status "Checking service status"
systemctl status polygon-edge --no-pager || true

# Display node information
print_status "Node setup complete!"
print_status "=== Service Information ==="
print_status "Status: sudo systemctl status polygon-edge"
print_status "Logs: polygon-logs [-f]"
print_status "Status: polygon-status"
print_status "Restart: polygon-restart"

print_status "=== Network Information ==="
print_status "JSON-RPC: http://localhost:8545"
print_status "GRPC: localhost:9632"
print_status "LibP2P: localhost:1478"
print_status "Prometheus: http://localhost:5001"

print_status "=== Important Files ==="
print_status "Config: /etc/polygon/config.yaml"
print_status "Data: /var/lib/polygon/"
print_status "Logs: /var/log/polygon/"
print_status "Service: /etc/systemd/system/polygon-edge.service"

# Log completion
log "Polygon Edge installation completed successfully"
print_status "Polygon Edge installation and setup complete!"

# Final check
print_status "Running final system check..."
if systemctl is-active --quiet polygon-edge; then
    print_status "✅ Polygon Edge service is running"
else
    print_error "❌ Polygon Edge service is not running"
    print_status "Check logs with: polygon-logs"
fi

print_status "Installation completed at $(date)"