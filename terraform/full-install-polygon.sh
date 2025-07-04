#!/bin/bash
# Improved Polygon Validator Installation Script with Multiple Fallback Strategies
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "$(date): [INFO] $1" >> /var/log/polygon-bootstrap.log
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "$(date): [WARNING] $1" >> /var/log/polygon-bootstrap.log
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "$(date): [ERROR] $1" >> /var/log/polygon-bootstrap.log
}

# Function to run command with timeout
run_with_timeout() {
    local timeout_duration=$1
    local command_description=$2
    shift 2
    
    print_status "Running: $command_description (timeout: ${timeout_duration}s)"
    
    if timeout $timeout_duration "$@"; then
        print_status "✅ $command_description completed successfully"
        return 0
    else
        print_error "❌ $command_description failed or timed out"
        return 1
    fi
}

# Function to check if binary works
verify_polygon_binary() {
    local binary_path=$1
    if [ -f "$binary_path" ] && [ -x "$binary_path" ]; then
        if $binary_path version >/dev/null 2>&1; then
            print_status "✅ Polygon binary verified: $binary_path"
            return 0
        fi
    fi
    print_error "❌ Polygon binary verification failed: $binary_path"
    return 1
}

# Installation Method 1: Use go install (fastest, most reliable)
install_via_go_install() {
    print_status "Attempting installation via go install..."
    
    if run_with_timeout 600 "go install polygon-edge" go install github.com/0xPolygon/polygon-edge@develop; then
        # Find where go install put the binary
        local go_bin_path
        if [ -f "/usr/local/go/bin/polygon-edge" ]; then
            go_bin_path="/usr/local/go/bin/polygon-edge"
        elif [ -f "/root/go/bin/polygon-edge" ]; then
            go_bin_path="/root/go/bin/polygon-edge"
        elif [ -f "$HOME/go/bin/polygon-edge" ]; then
            go_bin_path="$HOME/go/bin/polygon-edge"
        else
            print_error "Cannot find polygon-edge binary after go install"
            return 1
        fi
        
        # Copy to system location
        sudo cp "$go_bin_path" /usr/local/bin/
        sudo chmod +x /usr/local/bin/polygon-edge
        
        if verify_polygon_binary "/usr/local/bin/polygon-edge"; then
            print_status "✅ Installation via go install successful"
            return 0
        fi
    fi
    
    print_error "❌ Installation via go install failed"
    return 1
}

# Installation Method 2: Build from source with better error handling
install_via_source_build() {
    print_status "Attempting installation via source build..."
    
    cd /tmp
    
    # Clone with timeout
    if ! run_with_timeout 300 "git clone" git clone --depth 1 https://github.com/0xPolygon/polygon-edge.git; then
        return 1
    fi
    
    cd polygon-edge
    
    # Fix go.mod and build with timeout
    if run_with_timeout 60 "go mod tidy" go mod tidy; then
        if run_with_timeout 900 "go build" go build -o polygon-edge main.go; then
            if verify_polygon_binary "./polygon-edge"; then
                sudo cp polygon-edge /usr/local/bin/
                sudo chmod +x /usr/local/bin/polygon-edge
                print_status "✅ Installation via source build successful"
                return 0
            fi
        fi
    fi
    
    print_error "❌ Installation via source build failed"
    return 1
}

# Installation Method 3: Try pre-built binary (if available)
install_via_prebuilt_binary() {
    print_status "Attempting installation via pre-built binary..."
    
    # Try multiple possible download URLs
    local urls=(
        "https://github.com/0xPolygon/polygon-edge/releases/latest/download/polygon-edge_linux_amd64.tar.gz"
        "https://github.com/0xPolygon/polygon-edge/releases/download/v1.3.1/polygon-edge_1.3.1_linux_amd64.tar.gz"
        "https://github.com/0xPolygon/polygon-edge/releases/download/v1.3.0/polygon-edge_1.3.0_linux_amd64.tar.gz"
    )
    
    for url in "${urls[@]}"; do
        print_status "Trying URL: $url"
        cd /tmp
        
        if run_with_timeout 300 "download binary" wget -q "$url" -O polygon-edge.tar.gz; then
            if tar -xzf polygon-edge.tar.gz 2>/dev/null; then
                # Find the binary in extracted files
                local binary_file
                binary_file=$(find . -name "polygon-edge" -type f -executable 2>/dev/null | head -1)
                
                if [ -n "$binary_file" ] && verify_polygon_binary "$binary_file"; then
                    sudo cp "$binary_file" /usr/local/bin/
                    sudo chmod +x /usr/local/bin/polygon-edge
                    print_status "✅ Installation via pre-built binary successful"
                    return 0
                fi
            fi
        fi
        
        # Clean up failed attempt
        rm -f polygon-edge.tar.gz
    done
    
    print_error "❌ Installation via pre-built binary failed"
    return 1
}

print_status "Starting Enhanced Polygon Installation with Multiple Fallback Strategies"

# Update system with conflict resolution
print_status "Updating system packages"
sudo dnf update -y --allowerasing
sudo dnf groupinstall -y --allowerasing "Development Tools"
sudo dnf install -y --allowerasing wget curl git jq nc

# Install Go
print_status "Installing Go 1.24.4"
cd /tmp
if [ ! -f "go1.24.4.linux-amd64.tar.gz" ]; then
    run_with_timeout 300 "Download Go" wget -q https://go.dev/dl/go1.24.4.linux-amd64.tar.gz
fi
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.24.4.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee -a /etc/profile
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin

print_status "System update completed"

# Create polygon user and directories
print_status "Creating polygon user and directories"
sudo useradd -r -s /bin/false polygon 2>/dev/null || true
sudo mkdir -p /opt/polygon /var/lib/polygon /var/log/polygon /etc/polygon
sudo chown -R polygon:polygon /opt/polygon /var/lib/polygon /var/log/polygon /etc/polygon

# Try installation methods in order of preference
print_status "Starting Polygon Edge installation with fallback strategies..."

if install_via_go_install; then
    print_status "✅ Polygon Edge installed successfully via go install"
elif install_via_prebuilt_binary; then
    print_status "✅ Polygon Edge installed successfully via pre-built binary"
elif install_via_source_build; then
    print_status "✅ Polygon Edge installed successfully via source build"
else
    print_error "❌ All installation methods failed"
    print_error "Please check the logs and try manual installation"
    exit 1
fi

# Continue with configuration (rest of the script remains the same)
print_status "Configuring Polygon Edge..."

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

# Create utility scripts
print_status "Creating utility scripts"
sudo tee /usr/local/bin/polygon-status > /dev/null <<'EOF'
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
EOF

sudo chmod +x /usr/local/bin/polygon-status

# Configure firewall if needed
if systemctl is-active --quiet firewalld; then
    print_status "Configuring firewall"
    sudo firewall-cmd --permanent --add-port=8545/tcp --add-port=9632/tcp --add-port=1478/tcp --add-port=5001/tcp
    sudo firewall-cmd --reload
fi

# Start services
print_status "Starting Polygon Edge service"
sudo systemctl daemon-reload
sudo systemctl enable polygon-edge
sudo systemctl start polygon-edge

# Wait and verify
print_status "Waiting for service to start..."
sleep 30

if systemctl is-active --quiet polygon-edge; then
    print_status "✅ Polygon Edge service is running successfully"
    print_status "✅ Installation completed successfully!"
else
    print_error "❌ Polygon Edge service failed to start"
    print_status "Check logs with: sudo journalctl -u polygon-edge -f"
    exit 1
fi

print_status "=== Installation Complete ==="
print_status "Service status: sudo systemctl status polygon-edge"
print_status "Node status: polygon-status"
print_status "View logs: sudo journalctl -u polygon-edge -f"
print_status "JSON-RPC: http://localhost:8545"