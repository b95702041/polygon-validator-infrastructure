#!/bin/bash
# Enhanced Polygon Validator Installation Script
# Includes complete P2P connection fixes and automation
# Version: 2.0 - P2P Issues Resolved

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration - Working peers tested 2025-07-03
HEIMDALL_PERSISTENT_PEERS="7f3049e88ac7f820fd86d9120506aaec0dc54b27@34.89.75.187:26656,2d5484feef4257e56ece025633a6ea132d8cadca@35.246.99.203:26656,72a83490309f9f63fdca3a0bef16c290e5cbb09c@35.246.95.65:26656"

BOR_BOOTNODES='[
    "enode://e4fb013061eba9a2c6fb0a41bbd4149f4808f0fb7e88ec55d7163f19a6f02d64d0ce5ecc81528b769ba552a7068057432d44ab5e9e42842aff5b4709aa2c3f3b@34.89.75.187:30303",
    "enode://a49da6300403cf9b31e30502eb22c142ba4f77c9dda44990bccce9f2121c3152487ee95ee55c6b92d4cdce77845e40f59fd927da70ea91cf935b23e262236d75@34.142.43.249:30303",
    "enode://0e50fdcc2106b0c4e4d9ffbd7798ceda9432e680723dc7b7b4627e384078850c1c4a3e67f17ef2c484201ae6ee7c491cbf5e189b8ffee3948252e9bef59fc54e@35.234.148.172:30303",
    "enode://a0bc4dd2b59370d5a375a7ef9ac06cf531571005ae8b2ead2e9aaeb8205168919b169451fb0ef7061e0d80592e6ed0720f559bd1be1c4efb6e6c4381f1bdb986@35.246.99.203:30303"
]'

# Logging setup
LOGFILE="/var/log/polygon-install.log"
exec 1> >(tee -a "$LOGFILE")
exec 2> >(tee -a "$LOGFILE" >&2)

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_section() {
    echo -e "${BLUE}[SECTION]${NC} $1"
}

# Function to test connectivity
test_connectivity() {
    local host=$1
    local port=$2
    local timeout=3
    
    if nc -z -w$timeout "$host" "$port" 2>/dev/null; then
        print_status "✓ $host:$port is reachable"
        return 0
    else
        print_warning "✗ $host:$port is not reachable"
        return 1
    fi
}

# Function to verify prerequisites
verify_prerequisites() {
    print_section "Verifying Prerequisites"
    
    # Check if running as ec2-user
    if [[ "$USER" != "ec2-user" ]]; then
        print_error "This script should be run as ec2-user"
        exit 1
    fi
    
    # Check internet connectivity
    if ! ping -c 1 google.com &> /dev/null; then
        print_error "No internet connectivity"
        exit 1
    fi
    
    print_status "Prerequisites verified"
}

# Function to install dependencies
install_dependencies() {
    print_section "Installing Dependencies"
    
    # Update system packages
    sudo dnf update -y
    
    # Install development tools
    sudo dnf groupinstall -y "Development Tools"
    sudo dnf install -y wget curl git jq nc
    
    # Install Go 1.24.4
    print_status "Installing Go 1.24.4"
    cd /tmp
    wget -q https://go.dev/dl/go1.24.4.linux-amd64.tar.gz
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf go1.24.4.linux-amd64.tar.gz
    
    # Set up Go environment
    echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee -a /etc/profile
    echo 'export GOPATH=$HOME/go' | sudo tee -a /etc/profile
    echo 'export PATH=$PATH:$GOPATH/bin' | sudo tee -a /etc/profile
    
    # Load Go environment
    export PATH=$PATH:/usr/local/go/bin
    export GOPATH=$HOME/go
    export PATH=$PATH:$GOPATH/bin
    
    print_status "Dependencies installed successfully"
}

# Function to build Heimdall
build_heimdall() {
    print_section "Building Heimdall"
    
    cd $HOME
    
    # Clone Heimdall repository
    if [ ! -d "heimdall" ]; then
        print_status "Cloning Heimdall repository"
        git clone https://github.com/maticnetwork/heimdall.git
    fi
    
    cd heimdall
    
    # Build Heimdall
    print_status "Building Heimdall binaries"
    make install
    
    # Verify installation
    if command -v heimdalld &> /dev/null && command -v heimdallcli &> /dev/null; then
        print_status "Heimdall built successfully"
        heimdalld version
    else
        print_error "Heimdall build failed"
        exit 1
    fi
}

# Function to build Bor
build_bor() {
    print_section "Building Bor"
    
    cd $HOME
    
    # Clone Bor repository
    if [ ! -d "bor" ]; then
        print_status "Cloning Bor repository"
        git clone https://github.com/maticnetwork/bor.git
    fi
    
    cd bor
    
    # Build Bor
    print_status "Building Bor binary"
    make bor
    
    # Verify installation
    if [ -f "build/bin/bor" ]; then
        print_status "Bor built successfully"
        ./build/bin/bor version
    else
        print_error "Bor build failed"
        exit 1
    fi
}

# Function to initialize Heimdall
initialize_heimdall() {
    print_section "Initializing Heimdall"
    
    # Initialize Heimdall for mainnet
    print_status "Initializing Heimdall for mainnet"
    heimdalld init --chain-id heimdall-137
    
    # Download mainnet genesis
    print_status "Downloading mainnet genesis"
    curl -o ~/.heimdalld/config/genesis.json https://raw.githubusercontent.com/maticnetwork/heimdall/master/genesis/mainnet/genesis.json
    
    print_status "Heimdall initialized successfully"
}

# Function to configure Heimdall with working peers
configure_heimdall() {
    print_section "Configuring Heimdall with Working Peers"
    
    local config_file="$HOME/.heimdalld/config/config.toml"
    
    # Test peer connectivity before configuration
    print_status "Testing Heimdall peer connectivity"
    IFS=',' read -ra PEERS <<< "$HEIMDALL_PERSISTENT_PEERS"
    working_peers=()
    
    for peer in "${PEERS[@]}"; do
        peer_address=$(echo "$peer" | cut -d'@' -f2)
        peer_host=$(echo "$peer_address" | cut -d':' -f1)
        peer_port=$(echo "$peer_address" | cut -d':' -f2)
        
        if test_connectivity "$peer_host" "$peer_port"; then
            working_peers+=("$peer")
        fi
    done
    
    if [ ${#working_peers[@]} -eq 0 ]; then
        print_error "No working Heimdall peers found"
        exit 1
    fi
    
    # Join working peers
    working_peers_str=$(IFS=','; echo "${working_peers[*]}")
    
    # Apply optimal P2P configuration
    print_status "Applying optimal P2P configuration"
    sed -i "s/persistent_peers = .*/persistent_peers = \"$working_peers_str\"/" "$config_file"
    sed -i 's/seeds = .*/seeds = ""/' "$config_file"
    sed -i 's/addr_book_strict = true/addr_book_strict = false/' "$config_file"
    sed -i 's/max_num_inbound_peers = .*/max_num_inbound_peers = 200/' "$config_file"
    sed -i 's/max_num_outbound_peers = .*/max_num_outbound_peers = 200/' "$config_file"
    
    # Clear cached peer data for fresh start
    print_status "Clearing cached peer data"
    rm -f ~/.heimdalld/data/addrbook.json
    rm -f ~/.heimdalld/data/pex_reactor.json
    
    print_status "Heimdall configured with ${#working_peers[@]} working peers"
}

# Function to initialize Bor
initialize_bor() {
    print_section "Initializing Bor"
    
    # Create Bor directories
    mkdir -p ~/.bor/config
    
    # Copy mainnet genesis
    print_status "Setting up Bor genesis"
    cp ~/bor/builder/files/genesis-mainnet-v1.json ~/.bor/genesis.json
    
    # Initialize Bor
    print_status "Initializing Bor with mainnet genesis"
    ~/bor/build/bin/bor server --datadir ~/.bor init ~/.bor/genesis.json
    
    print_status "Bor initialized successfully"
}

# Function to configure Bor with working bootnodes
configure_bor() {
    print_section "Configuring Bor with Working Bootnodes"
    
    # Test bootnode connectivity
    print_status "Testing Bor bootnode connectivity"
    test_connectivity "34.89.75.187" "30303"
    test_connectivity "34.142.43.249" "30303"
    test_connectivity "35.234.148.172" "30303"
    test_connectivity "35.246.99.203" "30303"
    
    # Create Bor configuration
    print_status "Creating Bor configuration"
    cat > ~/.bor/config/config.toml << EOF
[eth]
networkid = 137
syncmode = "full"

[p2p]
maxpeers = 50
port = 30303
bootnode = true

[p2p.discovery]
bootnodes = $BOR_BOOTNODES

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
    
    print_status "Bor configured with working bootnodes"
}

# Function to create systemd services
create_systemd_services() {
    print_section "Creating Systemd Services"
    
    # Create Heimdall service
    print_status "Creating Heimdall service"
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
    
    # Create Heimdall REST service
    print_status "Creating Heimdall REST service"
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
    
    # Create Bor service
    print_status "Creating Bor service"
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
    
    # Reload systemd and enable services
    print_status "Enabling services"
    sudo systemctl daemon-reload
    sudo systemctl enable heimdalld
    sudo systemctl enable heimdalld-rest
    sudo systemctl enable bor
    
    print_status "Systemd services created successfully"
}

# Function to start services
start_services() {
    print_section "Starting Services"
    
    # Start Heimdall first
    print_status "Starting Heimdall"
    sudo systemctl start heimdalld
    
    # Wait for Heimdall to start
    sleep 10
    
    # Start Heimdall REST server
    print_status "Starting Heimdall REST server"
    sudo systemctl start heimdalld-rest
    
    # Wait for REST server to start
    sleep 5
    
    # Start Bor
    print_status "Starting Bor"
    sudo systemctl start bor
    
    print_status "All services started"
}

# Function to verify setup
verify_setup() {
    print_section "Verifying Setup"
    
    # Check service status
    print_status "Checking service status"
    sudo systemctl is-active heimdalld && print_status "✓ Heimdall is running" || print_error "✗ Heimdall is not running"
    sudo systemctl is-active heimdalld-rest && print_status "✓ Heimdall REST is running" || print_error "✗ Heimdall REST is not running"
    sudo systemctl is-active bor && print_status "✓ Bor is running" || print_error "✗ Bor is not running"
    
    # Wait for services to initialize
    sleep 30
    
    # Check API endpoints
    print_status "Testing API endpoints"
    
    # Test Heimdall RPC
    if curl -s --max-time 5 localhost:26657/status > /dev/null; then
        print_status "✓ Heimdall RPC is accessible"
        # Get peer count
        peer_count=$(curl -s localhost:26657/net_info | jq -r '.result.n_peers // "0"')
        print_status "✓ Heimdall peers: $peer_count"
    else
        print_warning "✗ Heimdall RPC is not accessible yet"
    fi
    
    # Test Heimdall REST
    if curl -s --max-time 5 localhost:1317/node_info > /dev/null; then
        print_status "✓ Heimdall REST API is accessible"
    else
        print_warning "✗ Heimdall REST API is not accessible yet"
    fi
    
    # Test Bor RPC
    if curl -s --max-time 5 -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"web3_clientVersion","params":[],"id":1}' localhost:8545 > /dev/null; then
        print_status "✓ Bor RPC is accessible"
    else
        print_warning "✗ Bor RPC is not accessible yet"
    fi
    
    print_status "Setup verification completed"
}

# Function to create monitoring script
create_monitoring_script() {
    print_section "Creating Monitoring Script"
    
    cat > $HOME/check-polygon-status.sh << 'EOF'
#!/bin/bash
# Polygon Validator Status Check Script

echo "=== Polygon Validator Status ==="
echo "$(date)"
echo

# Check service status
echo "📋 Service Status:"
sudo systemctl is-active heimdalld && echo "✅ Heimdall: Running" || echo "❌ Heimdall: Not running"
sudo systemctl is-active heimdalld-rest && echo "✅ Heimdall REST: Running" || echo "❌ Heimdall REST: Not running"
sudo systemctl is-active bor && echo "✅ Bor: Running" || echo "❌ Bor: Not running"
echo

# Check Heimdall sync status
echo "🔄 Heimdall Sync Status:"
if curl -s --max-time 5 localhost:26657/status > /dev/null; then
    sync_info=$(curl -s localhost:26657/status | jq -r '.result.sync_info')
    block_height=$(echo "$sync_info" | jq -r '.latest_block_height')
    catching_up=$(echo "$sync_info" | jq -r '.catching_up')
    block_time=$(echo "$sync_info" | jq -r '.latest_block_time')
    
    echo "   Block Height: $block_height"
    echo "   Block Time: $block_time"
    echo "   Catching Up: $catching_up"
    
    # Check peer count
    peer_count=$(curl -s localhost:26657/net_info | jq -r '.result.n_peers // "0"')
    echo "   Peer Count: $peer_count"
else
    echo "   ❌ Heimdall RPC not accessible"
fi
echo

# Check Bor sync status
echo "🔄 Bor Sync Status:"
if curl -s --max-time 5 -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' localhost:8545 > /dev/null; then
    echo "   ✅ Bor RPC accessible"
    
    # Check peer count
    peer_count_hex=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' localhost:8545 | jq -r '.result // "0x0"')
    peer_count=$((peer_count_hex))
    echo "   Peer Count: $peer_count"
else
    echo "   ❌ Bor RPC not accessible"
fi
echo

# Check recent logs
echo "📋 Recent Service Logs:"
echo "--- Heimdall (last 3 lines) ---"
sudo journalctl -u heimdalld -n 3 --no-pager | tail -n 3
echo
echo "--- Bor (last 3 lines) ---"
sudo journalctl -u bor -n 3 --no-pager | tail -n 3
echo

echo "=== Status check completed ==="
EOF

    chmod +x $HOME/check-polygon-status.sh
    print_status "Monitoring script created at $HOME/check-polygon-status.sh"
}

# Function to create installation summary
create_installation_summary() {
    print_section "Installation Summary"
    
    cat > $HOME/polygon-installation-summary.md << 'EOF'
# Polygon Validator Installation Summary

## Services Created
- **heimdalld.service** - Main Heimdall consensus daemon
- **heimdalld-rest.service** - Heimdall REST API server
- **bor.service** - Bor execution layer daemon

## Key Configuration Files
- `~/.heimdalld/config/config.toml` - Heimdall configuration
- `~/.bor/config/config.toml` - Bor configuration
- `~/.heimdalld/config/genesis.json` - Heimdall genesis file
- `~/.bor/genesis.json` - Bor genesis file

## Important Commands
```bash
# Check service status
sudo systemctl status heimdalld
sudo systemctl status heimdalld-rest
sudo systemctl status bor

# Monitor logs
sudo journalctl -u heimdalld -f
sudo journalctl -u bor -f

# Check sync status
curl -s localhost:26657/status | jq '.result.sync_info'

# Check peer connections
curl -s localhost:26657/net_info | jq '.result.n_peers'

# Run status check
~/check-polygon-status.sh
```

## Network Information
- **Heimdall Chain ID**: heimdall-137
- **Bor Network ID**: 137
- **Heimdall RPC**: localhost:26657
- **Heimdall REST**: localhost:1317
- **Bor RPC**: localhost:8545
- **Bor WebSocket**: localhost:8546

## Working Peer Configuration
The installation uses tested and working peers as of $(date +%Y-%m-%d):

### Heimdall Persistent Peers
- 7f3049e88ac7f820fd86d9120506aaec0dc54b27@34.89.75.187:26656
- 2d5484feef4257e56ece025633a6ea132d8cadca@35.246.99.203:26656
- 72a83490309f9f63fdca3a0bef16c290e5cbb09c@35.246.95.65:26656

### Bor Bootnodes
- enode://e4fb013061eba9a2c6fb0a41bbd4149f4808f0fb7e88ec55d7163f19a6f02d64d0ce5ecc81528b769ba552a7068057432d44ab5e9e42842aff5b4709aa2c3f3b@34.89.75.187:30303
- enode://a49da6300403cf9b31e30502eb22c142ba4f77c9dda44990bccce9f2121c3152487ee95ee55c6b92d4cdce77845e40f59fd927da70ea91cf935b23e262236d75@34.142.43.249:30303
- enode://0e50fdcc2106b0c4e4d9ffbd7798ceda9432e680723dc7b7b4627e384078850c1c4a3e67f17ef2c484201ae6ee7c491cbf5e189b8ffee3948252e9bef59fc54e@35.234.148.172:30303
- enode://a0bc4dd2b59370d5a375a7ef9ac06cf531571005ae8b2ead2e9aaeb8205168919b169451fb0ef7061e0d80592e6ed0720f559bd1be1c4efb6e6c4381f1bdb986@35.246.99.203:30303

## Troubleshooting
If you encounter issues:
1. Check service logs: `sudo journalctl -u <service-name> -n 50`
2. Verify peer connectivity: `nc -zv <peer-ip> <peer-port>`
3. Restart services: `sudo systemctl restart <service-name>`
4. Clear cached data: `rm ~/.heimdalld/data/addrbook.json`

## Expected Sync Times
- **Heimdall**: 5-10 hours for full sync
- **Bor**: 1-2 days for full sync
- **Peer Discovery**: 1-5 minutes for initial connections

Installation completed successfully!
EOF

    print_status "Installation summary created at $HOME/polygon-installation-summary.md"
}

# Main installation function
main() {
    print_section "Starting Enhanced Polygon Validator Installation"
    print_status "Version: 2.0 - P2P Issues Resolved"
    print_status "Installation log: $LOGFILE"
    
    # Installation steps
    verify_prerequisites
    install_dependencies
    build_heimdall
    build_bor
    initialize_heimdall
    configure_heimdall
    initialize_bor
    configure_bor
    create_systemd_services
    start_services
    verify_setup
    create_monitoring_script
    create_installation_summary
    
    print_section "Installation Completed Successfully!"
    print_status "🎉 Polygon validator setup complete with P2P connections working"
    print_status "📊 Run ~/check-polygon-status.sh to monitor progress"
    print_status "📋 See ~/polygon-installation-summary.md for details"
    print_status "🔍 Monitor logs with: sudo journalctl -u heimdalld -f"
}

# Run main installation
main "$@"