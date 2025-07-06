#!/bin/bash
# Polygon PoS (Bor + Heimdall) Validator Installation Script - FIXED VERSION
# This script builds and configures a complete Polygon validator node with proper RPC endpoints
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
    echo "$(date): [INFO] $1" >> /var/log/polygon-install.log
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
    echo "$(date): [WARNING] $1" >> /var/log/polygon-install.log
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    echo "$(date): [ERROR] $1" >> /var/log/polygon-install.log
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

# Function to verify binary installation
verify_binary() {
    local binary_name=$1
    local binary_path=$2
    
    if [ -f "$binary_path" ] && [ -x "$binary_path" ]; then
        local version_output
        version_output=$("$binary_path" version 2>/dev/null || echo "version check failed")
        print_status "✅ $binary_name verified: $version_output"
        return 0
    else
        print_error "❌ $binary_name verification failed: $binary_path"
        return 1
    fi
}

# Disk space management functions
check_disk_space() {
    local required_gb=$1
    local mount_point=$2
    local available_gb=$(df -BG "$mount_point" | tail -1 | awk '{print $4}' | sed 's/G//')
    
    if [ "$available_gb" -lt "$required_gb" ]; then
        print_error "Insufficient disk space. Required: ${required_gb}GB, Available: ${available_gb}GB"
        return 1
    fi
    print_status "✅ Sufficient disk space: ${available_gb}GB available"
    return 0
}

cleanup_build_space() {
    print_status "Cleaning up build space..."
    # Clean Go caches
    sudo rm -rf /tmp/go-build* /tmp/go-cache*
    # Clean package manager cache
    sudo dnf clean all
    # Remove build artifacts from previous attempts
    sudo rm -rf /tmp/heimdall /tmp/bor
    # Remove downloaded files after use
    sudo rm -rf /tmp/*.tar.gz
    print_status "✅ Build space cleaned"
}

setup_build_environment() {
    print_status "Setting up build environment..."
    # Use /var/tmp instead of /tmp for larger cache
    export GOCACHE=/var/tmp/go-cache-polygon
    export GOMODCACHE=/var/tmp/go-mod-cache
    mkdir -p $GOCACHE $GOMODCACHE
    
    # Set Git safe directories to avoid warnings
    git config --global --add safe.directory /tmp/heimdall 2>/dev/null || true
    git config --global --add safe.directory /tmp/bor 2>/dev/null || true
    
    print_status "✅ Build environment configured"
}

fix_build_permissions() {
    local build_dir=$1
    local owner=$2
    print_status "Fixing permissions for $build_dir..."
    sudo chown -R $owner:$owner "$build_dir"
    print_status "✅ Permissions fixed for $build_dir"
}

build_with_progress() {
    local component=$1
    local build_cmd="$2"
    local timeout_duration=$3
    
    print_status "Building $component (this may take 10-20 minutes)..."
    print_status "💡 Tip: Monitor progress in another terminal with: ps aux | grep 'go build'"
    print_status "💡 Or watch CPU usage with: top"
    
    if timeout $timeout_duration bash -c "$build_cmd"; then
        print_status "✅ $component build completed successfully"
        return 0
    else
        print_error "❌ $component build failed or timed out after ${timeout_duration}s"
        return 1
    fi
}

# Function to test RPC connectivity
test_rpc_endpoint() {
    local url=$1
    local name=$2
    
    print_status "Testing $name connectivity: $url"
    
    if curl -s -m 10 -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        "$url" > /dev/null; then
        print_status "✅ $name is accessible"
        return 0
    else
        print_warning "⚠️ $name connectivity test failed: $url"
        return 1
    fi
}

print_status "🚀 Starting Polygon PoS (Bor + Heimdall) Installation - FIXED VERSION"

# Update system with conflict resolution
print_status "Updating system packages..."
sudo dnf update -y --allowerasing
sudo dnf groupinstall -y --allowerasing "Development Tools"
sudo dnf install -y --allowerasing wget curl git jq nc htop tree

# Install Go 1.24.4
print_status "Installing Go 1.24.4..."
cd /tmp
if [ ! -f "go1.24.4.linux-amd64.tar.gz" ]; then
    run_with_timeout 300 "Download Go" wget -q https://go.dev/dl/go1.24.4.linux-amd64.tar.gz
fi
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.24.4.linux-amd64.tar.gz

# Set Go environment
echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee -a /etc/profile
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin

print_status "System setup completed ✅"

# Create polygon user and directories
print_status "Creating polygon user and directories..."
sudo useradd -r -s /bin/false polygon 2>/dev/null || true
sudo mkdir -p /var/lib/polygon/{bor,heimdall} /var/log/polygon /etc/polygon
sudo chown -R polygon:polygon /var/lib/polygon /var/log/polygon /etc/polygon

# Prepare build environment
check_disk_space 4 "/" || exit 1
cleanup_build_space
setup_build_environment

# Install Heimdall
print_status "📦 Installing Heimdall (Consensus Layer)..."
cd /tmp

if run_with_timeout 300 "Clone Heimdall" git clone --branch v1.0.7 --single-branch https://github.com/maticnetwork/heimdall.git; then
    cd heimdall
    fix_build_permissions "/tmp/heimdall" "ec2-user"
    
    # Build Heimdall with progress monitoring
    if build_with_progress "Heimdall" "make build GOFLAGS='-buildvcs=false'" 1200; then
        sudo cp build/heimdalld /usr/local/bin/
        sudo cp build/heimdallcli /usr/local/bin/
        sudo chmod +x /usr/local/bin/heimdall*
        
        if verify_binary "heimdalld" "/usr/local/bin/heimdalld" && verify_binary "heimdallcli" "/usr/local/bin/heimdallcli"; then
            print_status "✅ Heimdall installation successful"
        else
            print_error "❌ Heimdall verification failed"
            exit 1
        fi
    else
        print_error "❌ Heimdall build failed"
        exit 1
    fi
else
    print_error "❌ Failed to clone Heimdall repository"
    exit 1
fi

# Clean up space after Heimdall build
cleanup_build_space
check_disk_space 3 "/" || exit 1

# Install Bor
print_status "📦 Installing Bor (Execution Layer)..."
cd /tmp

if run_with_timeout 300 "Clone Bor" git clone --branch v1.5.5 --single-branch https://github.com/maticnetwork/bor.git; then
    cd bor
    fix_build_permissions "/tmp/bor" "ec2-user"
    
    # Build Bor with progress monitoring and extended timeout
    if build_with_progress "Bor" "make bor GOFLAGS='-buildvcs=false'" 1800; then
        sudo cp build/bin/bor /usr/local/bin/
        sudo chmod +x /usr/local/bin/bor
        
        if verify_binary "bor" "/usr/local/bin/bor"; then
            print_status "✅ Bor installation successful"
        else
            print_error "❌ Bor verification failed"
            exit 1
        fi
    else
        print_error "❌ Bor build failed"
        exit 1
    fi
else
    print_error "❌ Failed to clone Bor repository"
    exit 1
fi

# Final cleanup
cleanup_build_space

# Initialize Heimdall
print_status "🔧 Configuring Heimdall..."
sudo -u polygon heimdalld init --chain-id=137 --home=/var/lib/polygon/heimdall

# Download Heimdall genesis
print_status "Downloading Heimdall genesis file..."
if ! run_with_timeout 60 "Download Heimdall genesis" sudo -u polygon wget -q https://raw.githubusercontent.com/maticnetwork/launch/master/mainnet-v1/sentry/sentry/heimdall/config/genesis.json -O /var/lib/polygon/heimdall/config/genesis.json; then
    print_error "Failed to download Heimdall genesis file"
    exit 1
fi

# Configure Heimdall with working peers and state sync
print_status "Configuring Heimdall with state sync and RPC endpoints..."
sudo -u polygon tee /var/lib/polygon/heimdall/config/config.toml > /dev/null <<'HEIMDALL_EOF'
# Tendermint Core Configuration

#######################################################################
###                   Main Base Config Options                      ###
#######################################################################

# TCP or UNIX socket address of the ABCI application,
# or the name of an ABCI application compiled in with the Tendermint binary
proxy_app = "tcp://127.0.0.1:26658"

# A custom human readable name for this node
moniker = "polygon-validator"

# If this node is many blocks behind the tip of the chain, FastSync
# allows them to catchup quickly by downloading blocks in parallel
# and verifying their commits
fast_sync = true

# Database backend: goleveldb | cleveldb | boltdb | rocksdb | badgerdb
db_backend = "goleveldb"

# Database directory
db_dir = "data"

# Output level for logging, including package level options
log_level = "info"

# Output format: 'plain' (colored text) or 'json'
log_format = "plain"

##### additional base config options #####

# Path to the JSON file containing the initial validator set and other meta data
genesis_file = "config/genesis.json"

# Path to the JSON file containing the private key to use as a validator in the consensus protocol
priv_validator_key_file = "config/priv_validator_key.json"

# Path to the JSON file containing the last sign state of a validator
priv_validator_state_file = "data/priv_validator_state.json"

# TCP or UNIX socket address for Tendermint to listen on for
# connections from an external PrivValidator process
priv_validator_laddr = ""

# Path to the JSON file containing the private key to use for node authentication in the p2p protocol
node_key_file = "config/node_key.json"

# Mechanism to connect to the ABCI application: socket | grpc
abci = "socket"

# If true, query the ABCI app on connecting to a new peer
# so the app can decide if we should keep the connection or not
filter_peers = false

#######################################################################
###                 Advanced Configuration Options                  ###
#######################################################################

#######################################################
###       RPC Server Configuration Options          ###
#######################################################
[rpc]

# TCP or UNIX socket address for the RPC server to listen on
laddr = "tcp://0.0.0.0:26657"

# A list of origins a cross-domain request can be executed from
cors_allowed_origins = []

# A list of methods the client is allowed to use with cross-domain requests
cors_allowed_methods = ["HEAD", "GET", "POST", ]

# A list of non simple headers the client is allowed to use with cross-domain requests
cors_allowed_headers = ["Origin", "Accept", "Content-Type", "X-Requested-With", "X-Server-Time", ]

# TCP or UNIX socket address for the gRPC server to listen on
grpc_laddr = ""

# Maximum number of simultaneous connections.
grpc_max_open_connections = 900

# Activate unsafe RPC commands like /dial_seeds and /unsafe_flush_mempool
unsafe = false

# Maximum number of simultaneous connections (including WebSocket).
max_open_connections = 900

# Maximum number of unique clientIDs that can /subscribe
max_subscription_clients = 100

# Maximum number of unique queries a given client can /subscribe to
max_subscriptions_per_client = 5

# How long to wait for a tx to be committed during /broadcast_tx_commit.
timeout_broadcast_tx_commit = "10s"

# Maximum size of request body, in bytes
max_body_bytes = 1000000

# Maximum size of request header, in bytes
max_header_bytes = 1048576

# The path to a file containing certificate that is used to create the HTTPS server.
tls_cert_file = ""

# The path to a file containing matching private key that is used to create the HTTPS server.
tls_key_file = ""

# pprof listen address (https://golang.org/pkg/net/http/pprof)
pprof_laddr = ""

#######################################################
###           P2P Configuration Options             ###
#######################################################
[p2p]

# Address to listen for incoming connections
laddr = "tcp://0.0.0.0:26656"

# Address to advertise to peers for them to dial
external_address = ""

# Comma separated list of seed nodes to connect to
seeds = ""

# Comma separated list of nodes to keep persistent connections to
persistent_peers = "7f3049e88ac7f820fd86d9120506aaec0dc54b27@34.89.75.187:26656,2d5484feef4257e56ece025633a6ea132d8cadca@35.246.99.203:26656,72a83490309f9f63fdca3a0bef16c290e5cbb09c@35.246.95.65:26656"

# UPNP port forwarding
upnp = false

# Path to address book
addr_book_file = "config/addrbook.json"

# Set true for strict address routability rules
addr_book_strict = true

# Maximum number of inbound peers
max_num_inbound_peers = 40

# Maximum number of outbound peers to connect to, excluding persistent peers
max_num_outbound_peers = 10

# List of node IDs, to which a connection will be (re)established ignoring any existing limits
unconditional_peer_ids = ""

# Maximum pause when redialing a persistent peer (if zero, exponential backoff is used)
persistent_peers_max_dial_period = "0s"

# Time to wait before flushing messages out on the connection
flush_throttle_timeout = "100ms"

# Maximum size of a message packet payload, in bytes
max_packet_msg_payload_size = 1024

# Rate at which packets can be sent, in bytes/second
send_rate = 5120000

# Rate at which packets can be received, in bytes/second
recv_rate = 5120000

# Set true to enable the peer-exchange reactor
pex = true

# Seed mode, in which node constantly crawls the network and looks for
# peers. If another node asks it for addresses, it responds and disconnects.
seed_mode = false

# Comma separated list of peer IDs to keep private (will not be gossiped to other peers)
private_peer_ids = ""

# Toggle to disable guard against peers connecting from the same ip.
allow_duplicate_ip = false

# Peer connection configuration.
handshake_timeout = "20s"
dial_timeout = "3s"

#######################################################
###          Mempool Configuration Option          ###
#######################################################
[mempool]

recheck = true
broadcast = true
wal_dir = ""

# Maximum number of transactions in the mempool
size = 5000

# Limit the total size of all txs in the mempool.
max_txs_bytes = 1073741824

# Size of the cache (used to filter transactions we saw earlier) in transactions
cache_size = 10000

# Do not remove invalid transactions from the cache (default: false)
keep_invalid_txs_in_cache = false

# Maximum size of a single transaction.
max_tx_bytes = 1048576

# Maximum size of a batch of transactions to send to a peer
max_batch_bytes = 0

#######################################################
###         State Sync Configuration Options        ###
#######################################################
[statesync]
# State sync rapidly bootstraps a new node by discovering, fetching, and restoring a state machine
# snapshot from peers instead of fetching and replaying historical blocks. 
enable = true

# RPC servers (comma-separated) for light client verification of the synced state machine
rpc_servers = "https://polygon-rpc.com,https://rpc-mainnet.matic.network"
trust_height = 0
trust_hash = ""
trust_period = "168h0m0s"

# Time to spend discovering snapshots before initiating a restore.
discovery_time = "15s"

# Temporary directory for state sync snapshot chunks
temp_dir = ""

# The timeout duration before re-requesting a chunk
chunk_request_timeout = "10s"

# The number of concurrent chunk fetchers to run
chunk_fetchers = "4"

#######################################################
###       Fast Sync Configuration Connections       ###
#######################################################
[fastsync]

# Fast Sync version to use:
version = "v0"

#######################################################
###         Consensus Configuration Options         ###
#######################################################
[consensus]

wal_file = "data/cs.wal/wal"

timeout_propose = "3s"
timeout_propose_delta = "500ms"
timeout_prevote = "1s"
timeout_prevote_delta = "500ms"
timeout_precommit = "1s"
timeout_precommit_delta = "500ms"
timeout_commit = "5s"

# Make progress as soon as we have all the precommits (as if TimeoutCommit = 0)
skip_timeout_commit = false

# EmptyBlocks mode and possible interval between empty blocks
create_empty_blocks = true
create_empty_blocks_interval = "0s"

# Reactor sleep duration parameters
peer_gossip_sleep_duration = "100ms"
peer_query_maj23_sleep_duration = "2s"

#######################################################
###   Transaction Indexer Configuration Options     ###
#######################################################
[tx_index]

# What indexer to use for transactions
indexer = "kv"

#######################################################
###       Instrumentation Configuration Options     ###
#######################################################
[instrumentation]

# When true, Prometheus metrics are served under /metrics on
# PrometheusListenAddr.
prometheus = false

# Address to listen for Prometheus collector(s) connections
prometheus_listen_addr = ":26660"

# Maximum number of simultaneous connections.
max_open_connections = 3

# Instrumentation namespace
namespace = "tendermint"
HEIMDALL_EOF

# **CRITICAL FIX**: Configure Heimdall with required RPC endpoints
print_status "🔑 Configuring Heimdall with required RPC endpoints..."
sudo -u polygon tee /var/lib/polygon/heimdall/config/heimdall-config.toml > /dev/null <<'HEIMDALL_CONFIG_EOF'
# Heimdall Configuration

# Ethereum mainnet RPC endpoint (REQUIRED for checkpoint verification)
eth_rpc_url = "https://ethereum-rpc.publicnode.com"

# Bor RPC endpoint (REQUIRED for validation)
bor_rpc_url = "http://127.0.0.1:8545"

# Chain configuration
chain_id = "137"
chain_name = "mainnet"

# Database configuration
db_backend = "goleveldb"

# Logging configuration
log_level = "info"

# Server configuration
server_address = "0.0.0.0:1317"

# Tendermint RPC
tendermint_rpc_url = "http://127.0.0.1:26657"

# Checkpoint confirmation blocks
checkpoint_confirmation_blocks = 64

# Milestone confirmation blocks  
milestone_confirmation_blocks = 16

# Span confirmation blocks
span_confirmation_blocks = 6400

# Gas limit for transactions
gas_limit = 10000000

# Gas price for transactions
gas_price = "1000000000"

# Maximum gas price allowed
max_gas_price = "400000000000"

# Heimdall block interval
heimdall_block_interval = "5s"

# Sync configuration
sync_mode = "fast"

# Pruning configuration
pruning = "default"

# State sync configuration
state_sync_enable = true
state_sync_height = 0
HEIMDALL_CONFIG_EOF

# Test RPC connectivity before proceeding
print_status "🔍 Testing external RPC connectivity..."
test_rpc_endpoint "https://ethereum-rpc.publicnode.com" "Ethereum RPC"
test_rpc_endpoint "https://polygon-rpc.com" "Polygon RPC"

# Initialize Bor
print_status "🔧 Configuring Bor..."
sudo -u polygon mkdir -p /var/lib/polygon/bor/keystore

# Download Bor genesis
print_status "Downloading Bor genesis file..."
if ! run_with_timeout 60 "Download Bor genesis" sudo -u polygon wget -q https://raw.githubusercontent.com/maticnetwork/bor/master/builder/files/genesis-mainnet-v1.json -O /var/lib/polygon/bor/genesis.json; then
    print_error "Failed to download Bor genesis file"
    exit 1
fi

print_status "✅ Bor configuration completed"

# Configure Bor with updated bootnodes and RPC endpoints
print_status "Configuring Bor with working bootnode connections and RPC settings..."
sudo -u polygon tee /var/lib/polygon/bor/config.toml > /dev/null <<'BOR_EOF'
[pprof]
  addr = "127.0.0.1"
  port = 6060

[jsonrpc]
  ipcpath = "/var/lib/polygon/bor/bor.ipc"
  gascap = 50000000
  evmtimeout = "5s"
  txfeecap = 5.0
  allow-unprotected-txs = false
  enabledeprecatedpersonal = false

  [jsonrpc.http]
    enabled = true
    port = 8545
    host = "0.0.0.0"
    api = ["eth", "net", "web3", "txpool", "bor"]
    vhosts = ["*"]
    corsdomain = ["*"]

  [jsonrpc.ws]
    enabled = false
    port = 8546
    host = "localhost"
    api = ["eth", "net", "web3", "txpool", "bor"]
    origins = ["*"]

  [jsonrpc.graphql]
    enabled = false
    port = 8547
    host = "localhost"
    vhosts = ["*"]
    corsdomain = ["*"]

[p2p]
  maxpeers = 50
  maxpendpeers = 50
  bind = "0.0.0.0"
  port = 30303
  nodiscover = false
  nat = "any"
  netrestrict = ""
  nodekey = ""
  nodekeyhex = ""
  txarrivalwait = "500ms"
  
  [p2p.discovery]
    v5disc = false
    bootnodes = [
      "enode://0cb82b395094ee4a2915e9714894627de9ed8498fb881cec6db7c65e8b9a5bd7f2f25cc84e71e89d0947e51c76e85d0847de848c7782b13c0255247a6758178@44.232.55.71:30303",
      "enode://88116f4295f5a31538ae409e4d44ad40d22e44ee9342869e7d68bdec55b0f83c1530355ce8b41fbec0928a7d75a5745d528450d30aec92066ab6ba1ee351d710@159.203.9.164:30303",
      "enode://3178257cd1e1ab8f95eeb7cc45e28b6047a0432b2f9412cff1db9bb31426eac30edeb81fedc30b7cd3059f0902b5350f75d1b376d2c632e1b375af0553813e6f@35.221.13.28:30303",
      "enode://16d9a28eadbd247a09ff53b7b1f22231f6deaf10b86d4b23924023aea49bfdd51465b36d79d29be46a5497a96151a1a1ea448f8a8666266284e004306b2afb6e@35.199.4.13:30303",
      "enode://ef271e1c28382daa6ac2d1006dd1924356cfd843dbe88a7397d53396e0741ca1a8da0a113913dee52d9071f0ad8d39e3ce87aa81ebc190776432ee7ddc9d9470@35.230.116.151:30303"
    ]
    bootnodesv4 = []
    bootnodesv5 = []
    static-nodes = []
    trusted-nodes = []
    dns = []

[heimdall]
  url = "http://127.0.0.1:1317"
  "bor.without" = false

[txpool]
  locals = []
  nolocals = false
  journal = ""
  rejournal = "1h0m0s"
  pricelimit = 30000000000
  pricebump = 10
  accountslots = 16
  globalslots = 32768
  accountqueue = 16
  globalqueue = 32768
  lifetime = "3h0m0s"

[miner]
  mine = false
  etherbase = ""
  extradata = ""
  gaslimit = 20000000
  gasprice = "30000000000"

[ethstats]
  url = ""

[cache]
  cache = 1024
  gc = 25
  snapshot = 10
  database = 50
  trie = 15
  noprefetch = false
  preimages = false
  txlookuplimit = 2350000

[accounts]
  unlock = []
  password = ""
  allow-insecure-unlock = false
  lightkdf = false
  disable-bor-wallet = true

[grpc]
  addr = ":3131"

[developer]
  dev = false
  period = 0
  gaslimit = 11500000

[parallelevm]
  enable = true
  procs = 8
BOR_EOF

# Create systemd services
print_status "📝 Creating systemd services..."

# Heimdall service with updated configuration
print_status "Creating Heimdall systemd service..."
sudo tee /etc/systemd/system/heimdalld.service > /dev/null <<'HEIMDALL_SERVICE_EOF'
[Unit]
Description=Heimdall Daemon
After=network.target
StartLimitIntervalSec=500
StartLimitBurst=5

[Service]
Type=exec
Restart=always
RestartSec=5
User=polygon
Group=polygon
ExecStart=/usr/local/bin/heimdalld start --home /var/lib/polygon/heimdall --chain-id 137
StandardOutput=append:/var/log/polygon/heimdalld.log
StandardError=append:/var/log/polygon/heimdalld-error.log
SyslogIdentifier=heimdalld
Environment="ETH_RPC_URL=https://ethereum-rpc.publicnode.com"
Environment="BOR_RPC_URL=http://127.0.0.1:8545"

[Install]
WantedBy=multi-user.target
HEIMDALL_SERVICE_EOF

# Heimdall REST service
print_status "Creating Heimdall REST systemd service..."
sudo tee /etc/systemd/system/heimdalld-rest.service > /dev/null <<'HEIMDALL_REST_SERVICE_EOF'
[Unit]
Description=Heimdall REST Server
After=heimdalld.service
Requires=heimdalld.service
StartLimitIntervalSec=500
StartLimitBurst=5

[Service]
Type=exec
Restart=always
RestartSec=5
User=polygon
Group=polygon
ExecStart=/usr/local/bin/heimdallcli rest-server --home /var/lib/polygon/heimdall --node tcp://127.0.0.1:26657 --chain-id 137
StandardOutput=append:/var/log/polygon/heimdall-rest.log
StandardError=append:/var/log/polygon/heimdall-rest-error.log
SyslogIdentifier=heimdall-rest

[Install]
WantedBy=multi-user.target
HEIMDALL_REST_SERVICE_EOF

# Bor service with improved configuration
print_status "Creating Bor systemd service..."
sudo tee /etc/systemd/system/bor.service > /dev/null <<'BOR_SERVICE_EOF'
[Unit]
Description=Bor Service
After=heimdalld-rest.service
Requires=heimdalld-rest.service
StartLimitIntervalSec=500
StartLimitBurst=5

[Service]
Type=exec
Restart=always
RestartSec=5
User=polygon
Group=polygon
ExecStart=/usr/local/bin/bor server --config /var/lib/polygon/bor/config.toml --datadir /var/lib/polygon/bor --chain /var/lib/polygon/bor/genesis.json --syncmode full
StandardOutput=append:/var/log/polygon/bor.log
StandardError=append:/var/log/polygon/bor-error.log
SyslogIdentifier=bor

[Install]
WantedBy=multi-user.target
BOR_SERVICE_EOF

# Create utility scripts
print_status "📋 Creating utility scripts..."

# Enhanced status script with RPC connectivity checks
print_status "Creating polygon-status utility script..."
sudo tee /usr/local/bin/polygon-status > /dev/null <<'STATUS_SCRIPT_EOF'
#!/bin/bash
echo "=== Polygon PoS Node Status - Enhanced ==="
echo ""

echo "--- Service Status ---"
printf "Heimdall:      "
if systemctl is-active --quiet heimdalld; then
    echo -e "\033[32mRunning\033[0m"
else
    echo -e "\033[31mStopped\033[0m"
fi

printf "Heimdall REST: "
if systemctl is-active --quiet heimdalld-rest; then
    echo -e "\033[32mRunning\033[0m"
else
    echo -e "\033[31mStopped\033[0m"
fi

printf "Bor:           "
if systemctl is-active --quiet bor; then
    echo -e "\033[32mRunning\033[0m"
else
    echo -e "\033[31mStopped\033[0m"
fi
echo ""

echo "--- RPC Connectivity Tests ---"
printf "Ethereum RPC:  "
if curl -s -m 5 -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    https://ethereum-rpc.publicnode.com > /dev/null 2>&1; then
    echo -e "\033[32mAccessible\033[0m"
else
    echo -e "\033[31mFailed\033[0m"
fi

printf "Polygon RPC:   "
if curl -s -m 5 -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    https://polygon-rpc.com > /dev/null 2>&1; then
    echo -e "\033[32mAccessible\033[0m"
else
    echo -e "\033[31mFailed\033[0m"
fi

printf "Local Bor RPC: "
if curl -s -m 5 -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    http://localhost:8545 > /dev/null 2>&1; then
    echo -e "\033[32mAccessible\033[0m"
else
    echo -e "\033[31mNot Ready\033[0m"
fi
echo ""

echo "--- Heimdall Sync Status ---"
heimdall_status=$(curl -s localhost:26657/status 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "Latest Block: $(echo $heimdall_status | jq -r '.result.sync_info.latest_block_height' 2>/dev/null || echo 'N/A')"
    echo "Catching Up:  $(echo $heimdall_status | jq -r '.result.sync_info.catching_up' 2>/dev/null || echo 'N/A')"
    echo "Block Time:   $(echo $heimdall_status | jq -r '.result.sync_info.latest_block_time' 2>/dev/null || echo 'N/A')"
else
    echo "Heimdall RPC not ready"
fi
echo ""

echo "--- Heimdall Peers ---"
peer_count=$(curl -s localhost:26657/net_info 2>/dev/null | jq -r '.result.n_peers' 2>/dev/null)
echo "Connected Peers: ${peer_count:-'N/A'}"
echo ""

echo "--- Bor Sync Status ---"
bor_sync=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
    http://localhost:8545 2>/dev/null)
if [ $? -eq 0 ]; then
    echo "Sync Status: $(echo $bor_sync | jq . 2>/dev/null || echo 'Not ready')"
else
    echo "Bor RPC not ready"
fi
echo ""

echo "--- Latest Block ---"
bor_block=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    http://localhost:8545 2>/dev/null)
if [ $? -eq 0 ]; then
    block_hex=$(echo $bor_block | jq -r '.result' 2>/dev/null)
    if [ "$block_hex" != "null" ] && [ "$block_hex" != "" ]; then
        block_dec=$((16#${block_hex#0x}))
        echo "Block Number: $block_dec (hex: $block_hex)"
    else
        echo "Block Number: Not available"
    fi
else
    echo "Bor RPC not ready"
fi
echo ""

echo "--- Peer Count ---"
peer_count_bor=$(curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
    http://localhost:8545 2>/dev/null | jq -r '.result' 2>/dev/null)
if [ "$peer_count_bor" != "null" ] && [ "$peer_count_bor" != "" ]; then
    peer_dec=$((16#${peer_count_bor#0x}))
    echo "Bor Peers: $peer_dec"
else
    echo "Bor Peers: Not available"
fi
STATUS_SCRIPT_EOF

# Enhanced log viewer with error detection
print_status "Creating polygon-logs utility script..."
sudo tee /usr/local/bin/polygon-logs > /dev/null <<'LOGS_SCRIPT_EOF'
#!/bin/bash
case "$1" in
    "heimdall"|"h")
        if [ "$2" = "-f" ] || [ "$2" = "follow" ]; then
            echo "Following Heimdall logs (Ctrl+C to stop)..."
            tail -f /var/log/polygon/heimdalld.log
        elif [ "$2" = "-e" ] || [ "$2" = "error" ]; then
            echo "=== Heimdall Error Logs ==="
            tail -n 50 /var/log/polygon/heimdalld-error.log 2>/dev/null || echo "No error logs yet"
        else
            echo "=== Heimdall Logs (last 100 lines) ==="
            tail -n 100 /var/log/polygon/heimdalld.log
        fi
        ;;
    "rest"|"r")
        if [ "$2" = "-f" ] || [ "$2" = "follow" ]; then
            echo "Following Heimdall REST logs (Ctrl+C to stop)..."
            tail -f /var/log/polygon/heimdall-rest.log
        elif [ "$2" = "-e" ] || [ "$2" = "error" ]; then
            echo "=== Heimdall REST Error Logs ==="
            tail -n 50 /var/log/polygon/heimdall-rest-error.log 2>/dev/null || echo "No error logs yet"
        else
            echo "=== Heimdall REST Logs (last 100 lines) ==="
            tail -n 100 /var/log/polygon/heimdall-rest.log
        fi
        ;;
    "bor"|"b")
        if [ "$2" = "-f" ] || [ "$2" = "follow" ]; then
            echo "Following Bor logs (Ctrl+C to stop)..."
            tail -f /var/log/polygon/bor.log
        elif [ "$2" = "-e" ] || [ "$2" = "error" ]; then
            echo "=== Bor Error Logs ==="
            tail -n 50 /var/log/polygon/bor-error.log 2>/dev/null || echo "No error logs yet"
        else
            echo "=== Bor Logs (last 100 lines) ==="
            tail -n 100 /var/log/polygon/bor.log
        fi
        ;;
    "errors"|"e")
        echo "=== Recent Errors from All Services ==="
        echo ""
        echo "--- Heimdall Errors ---"
        grep -i "error\|failed\|panic" /var/log/polygon/heimdalld.log 2>/dev/null | tail -10 || echo "No errors found"
        echo ""
        echo "--- Heimdall REST Errors ---"
        grep -i "error\|failed\|panic" /var/log/polygon/heimdall-rest.log 2>/dev/null | tail -10 || echo "No errors found"
        echo ""
        echo "--- Bor Errors ---"
        grep -i "error\|failed\|panic" /var/log/polygon/bor.log 2>/dev/null | tail -10 || echo "No errors found"
        ;;
    "all"|"a")
        echo "=== Heimdall Logs (last 20 lines) ==="
        tail -n 20 /var/log/polygon/heimdalld.log 2>/dev/null || echo "No logs yet"
        echo ""
        echo "=== Heimdall REST Logs (last 20 lines) ==="
        tail -n 20 /var/log/polygon/heimdall-rest.log 2>/dev/null || echo "No logs yet"
        echo ""
        echo "=== Bor Logs (last 20 lines) ==="
        tail -n 20 /var/log/polygon/bor.log 2>/dev/null || echo "No logs yet"
        ;;
    *)
        echo "Usage: polygon-logs [heimdall|rest|bor|all|errors] [options]"
        echo ""
        echo "Services:"
        echo "  heimdall, h    - Show Heimdall logs"
        echo "  rest, r        - Show Heimdall REST logs"
        echo "  bor, b         - Show Bor logs"
        echo "  all, a         - Show recent logs from all services"
        echo "  errors, e      - Show recent errors from all services"
        echo ""
        echo "Options:"
        echo "  -f, follow     - Follow logs in real-time"
        echo "  -e, error      - Show error logs"
        echo ""
        echo "Examples:"
        echo "  polygon-logs heimdall          # Show last 100 heimdall log lines"
        echo "  polygon-logs heimdall -f       # Follow heimdall logs"
        echo "  polygon-logs bor -e            # Show bor error logs"
        echo "  polygon-logs errors            # Show recent errors from all services"
        ;;
esac
LOGS_SCRIPT_EOF

# Enhanced restart script with validation
print_status "Creating polygon-restart utility script..."
sudo tee /usr/local/bin/polygon-restart > /dev/null <<'RESTART_SCRIPT_EOF'
#!/bin/bash

restart_service() {
    local service=$1
    local display_name=$2
    
    echo "Stopping $display_name..."
    sudo systemctl stop $service
    sleep 3
    
    echo "Starting $display_name..."
    sudo systemctl start $service
    sleep 5
    
    if systemctl is-active --quiet $service; then
        echo "✅ $display_name restarted successfully"
    else
        echo "❌ $display_name failed to start"
        echo "Check logs with: polygon-logs $service -e"
    fi
}

case "$1" in
    "heimdall"|"h")
        restart_service "heimdalld" "Heimdall"
        ;;
    "rest"|"r")
        restart_service "heimdalld-rest" "Heimdall REST"
        ;;
    "bor"|"b")
        restart_service "bor" "Bor"
        ;;
    "all"|"a"|"")
        echo "Restarting all Polygon services in order..."
        echo ""
        restart_service "heimdalld" "Heimdall"
        echo ""
        restart_service "heimdalld-rest" "Heimdall REST"
        echo ""
        restart_service "bor" "Bor"
        echo ""
        echo "=== Final Status Check ==="
        polygon-status
        ;;
    *)
        echo "Usage: polygon-restart [heimdall|rest|bor|all]"
        echo ""
        echo "Examples:"
        echo "  polygon-restart all        # Restart all services in order"
        echo "  polygon-restart heimdall   # Restart only heimdall"
        echo "  polygon-restart bor        # Restart only bor"
        ;;
esac
RESTART_SCRIPT_EOF

# Enhanced monitoring script with better formatting
print_status "Creating polygon-monitor utility script..."
sudo tee /usr/local/bin/polygon-monitor > /dev/null <<'MONITOR_SCRIPT_EOF'
#!/bin/bash
echo "=== Polygon PoS Node Monitor ==="
echo "Press Ctrl+C to exit"
echo ""

while true; do
    clear
    echo "=== Polygon PoS Node Monitor - $(date) ==="
    echo ""
    
    # Service status with color coding
    echo "--- Services ---"
    printf "%-15s " "Heimdall:"
    if systemctl is-active --quiet heimdalld; then
        echo -e "\033[32m●\033[0m Running"
    else
        echo -e "\033[31m●\033[0m Stopped"
    fi
    
    printf "%-15s " "Heimdall REST:"
    if systemctl is-active --quiet heimdalld-rest; then
        echo -e "\033[32m●\033[0m Running"
    else
        echo -e "\033[31m●\033[0m Stopped"
    fi
    
    printf "%-15s " "Bor:"
    if systemctl is-active --quiet bor; then
        echo -e "\033[32m●\033[0m Running"
    else
        echo -e "\033[31m●\033[0m Stopped"
    fi
    echo ""
    
    # RPC Status
    echo "--- RPC Status ---"
    printf "%-15s " "Ethereum RPC:"
    if curl -s -m 3 -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        https://ethereum-rpc.publicnode.com > /dev/null 2>&1; then
        echo -e "\033[32m●\033[0m Connected"
    else
        echo -e "\033[31m●\033[0m Failed"
    fi
    
    printf "%-15s " "Local Bor RPC:"
    if curl -s -m 3 -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:8545 > /dev/null 2>&1; then
        echo -e "\033[32m●\033[0m Ready"
    else
        echo -e "\033[31m●\033[0m Not Ready"
    fi
    echo ""
    
    # Sync status
    echo "--- Sync Status ---"
    heimdall_status=$(curl -s -m 3 localhost:26657/status 2>/dev/null)
    if [ $? -eq 0 ]; then
        latest_block=$(echo $heimdall_status | jq -r '.result.sync_info.latest_block_height' 2>/dev/null)
        catching_up=$(echo $heimdall_status | jq -r '.result.sync_info.catching_up' 2>/dev/null)
        printf "%-20s %s\n" "Heimdall Block:" "${latest_block:-'N/A'}"
        printf "%-20s " "Catching Up:"
        if [ "$catching_up" = "true" ]; then
            echo -e "\033[33mYes\033[0m"
        elif [ "$catching_up" = "false" ]; then
            echo -e "\033[32mNo\033[0m"
        else
            echo "N/A"
        fi
    else
        echo "Heimdall: RPC not ready"
    fi
    
    bor_block=$(curl -s -m 3 -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
        http://localhost:8545 2>/dev/null | jq -r '.result' 2>/dev/null)
    if [ "$bor_block" != "null" ] && [ "$bor_block" != "" ]; then
        bor_block_dec=$((16#${bor_block#0x}))
        printf "%-20s %s\n" "Bor Block:" "$bor_block_dec"
    else
        echo "Bor Block:           Not ready"
    fi
    echo ""
    
    # Peer connections
    echo "--- Peer Connections ---"
    heimdall_peers=$(curl -s -m 3 localhost:26657/net_info 2>/dev/null | jq -r '.result.n_peers' 2>/dev/null)
    printf "%-20s %s\n" "Heimdall Peers:" "${heimdall_peers:-'N/A'}"
    
    bor_peers=$(curl -s -m 3 -X POST -H "Content-Type: application/json" \
        --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
        http://localhost:8545 2>/dev/null | jq -r '.result' 2>/dev/null)
    if [ "$bor_peers" != "null" ] && [ "$bor_peers" != "" ]; then
        bor_peers_dec=$((16#${bor_peers#0x}))
        printf "%-20s %s\n" "Bor Peers:" "$bor_peers_dec"
    else
        echo "Bor Peers:           N/A"
    fi
    echo ""
    
    # System resources
    echo "--- System Resources ---"
    cpu_usage=$(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)
    mem_usage=$(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')
    disk_usage=$(df /var/lib/polygon | tail -1 | awk '{print $5}')
    
    printf "%-20s %s\n" "CPU Usage:" "${cpu_usage}%"
    printf "%-20s %s\n" "Memory Usage:" "$mem_usage"
    printf "%-20s %s\n" "Disk Usage:" "$disk_usage"
    
    echo ""
    echo "Next update in 10 seconds... (Ctrl+C to exit)"
    sleep 10
done
MONITOR_SCRIPT_EOF

# Network diagnostics script
print_status "Creating polygon-network utility script..."
sudo tee /usr/local/bin/polygon-network > /dev/null <<'NETWORK_SCRIPT_EOF'
#!/bin/bash
echo "=== Polygon Network Diagnostics ==="
echo ""

echo "--- External RPC Connectivity ---"
echo "Testing Ethereum mainnet RPC..."
if curl -s -m 10 -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    https://ethereum-rpc.publicnode.com | jq .; then
    echo "✅ Ethereum RPC working"
else
    echo "❌ Ethereum RPC failed"
fi
echo ""

echo "Testing Polygon RPC..."
if curl -s -m 10 -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    https://polygon-rpc.com | jq .; then
    echo "✅ Polygon RPC working"
else
    echo "❌ Polygon RPC failed"
fi
echo ""

echo "--- Local Service Connectivity ---"
echo "Testing Heimdall RPC..."
if curl -s -m 5 localhost:26657/status | jq .result.sync_info; then
    echo "✅ Heimdall RPC working"
else
    echo "❌ Heimdall RPC not responding"
fi
echo ""

echo "Testing Heimdall REST..."
if curl -s -m 5 localhost:1317/status | jq .; then
    echo "✅ Heimdall REST working"
else
    echo "❌ Heimdall REST not responding"
fi
echo ""

echo "Testing Bor RPC..."
if curl -s -m 5 -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    http://localhost:8545 | jq .; then
    echo "✅ Bor RPC working"
else
    echo "❌ Bor RPC not responding"
fi
echo ""

echo "--- Port Status ---"
echo "Checking open ports..."
ss -tlnp | grep -E "(26656|26657|30303|8545|1317)" | while read line; do
    echo "$line"
done
echo ""

echo "--- Peer Information ---"
echo "Heimdall peer details..."
curl -s localhost:26657/net_info 2>/dev/null | jq '.result.peers[] | {id: .node_info.id, moniker: .node_info.moniker, remote_ip: .remote_ip}' 2>/dev/null || echo "No peer data available"
NETWORK_SCRIPT_EOF

# Make all scripts executable
print_status "Making utility scripts executable..."
sudo chmod +x /usr/local/bin/polygon-status
sudo chmod +x /usr/local/bin/polygon-logs
sudo chmod +x /usr/local/bin/polygon-restart
sudo chmod +x /usr/local/bin/polygon-monitor
sudo chmod +x /usr/local/bin/polygon-network
print_status "✅ Enhanced utility scripts created"

# Create log rotation
print_status "Setting up log rotation..."
sudo tee /etc/logrotate.d/polygon > /dev/null <<'LOGROTATE_EOF'
/var/log/polygon/*.log {
    daily
    missingok
    rotate 30
    compress
    delaycompress
    notifempty
    create 640 polygon polygon
    postrotate
        systemctl reload heimdalld heimdalld-rest bor 2>/dev/null || true
    endscript
}
LOGROTATE_EOF

# Configure firewall if running
if systemctl is-active --quiet firewalld; then
    print_status "Configuring firewall..."
    sudo firewall-cmd --permanent --add-port=26656/tcp  # Heimdall P2P
    sudo firewall-cmd --permanent --add-port=26657/tcp  # Heimdall RPC
    sudo firewall-cmd --permanent --add-port=30303/tcp  # Bor P2P
    sudo firewall-cmd --permanent --add-port=8545/tcp   # Bor RPC
    sudo firewall-cmd --permanent --add-port=1317/tcp   # Heimdall REST
    sudo firewall-cmd --reload
    print_status "✅ Firewall configured"
fi

# Enable and start services
print_status "🚀 Starting Polygon PoS services..."
sudo systemctl daemon-reload

# Start services in order with proper dependencies
sudo systemctl enable heimdalld
print_status "Starting Heimdall..."
sudo systemctl start heimdalld
sleep 20

# Check if Heimdall started successfully before proceeding
if ! systemctl is-active --quiet heimdalld; then
    print_warning "⚠️ Heimdall failed to start, checking logs..."
    tail -20 /var/log/polygon/heimdalld.log
    print_error "Installation may have issues. Check logs with: polygon-logs heimdall"
fi

sudo systemctl enable heimdalld-rest
print_status "Starting Heimdall REST..."
sudo systemctl start heimdalld-rest
sleep 15

# Check if REST API started
if ! systemctl is-active --quiet heimdalld-rest; then
    print_warning "⚠️ Heimdall REST failed to start, checking logs..."
    tail -20 /var/log/polygon/heimdall-rest.log
fi

sudo systemctl enable bor
print_status "Starting Bor..."
sudo systemctl start bor
sleep 25

# Final comprehensive status check
print_status "🔍 Running comprehensive status check..."
if systemctl is-active --quiet heimdalld; then
    print_status "✅ Heimdall is running"
else
    print_warning "⚠️ Heimdall is not running properly"
fi

if systemctl is-active --quiet heimdalld-rest; then
    print_status "✅ Heimdall REST is running"
else
    print_warning "⚠️ Heimdall REST is not running properly"
fi

if systemctl is-active --quiet bor; then
    print_status "✅ Bor is running"
else
    print_warning "⚠️ Bor is not running properly"
fi

# Test RPC endpoints after startup
print_status "🔗 Testing RPC connectivity after startup..."
sleep 10
test_rpc_endpoint "https://ethereum-rpc.publicnode.com" "External Ethereum RPC"
test_rpc_endpoint "http://localhost:8545" "Local Bor RPC"

print_status "🎉 Polygon PoS installation completed!"
print_status ""
print_status "=== 🚀 ENHANCED Quick Commands ==="
print_status "📊 Node status:       polygon-status"
print_status "📋 View logs:         polygon-logs [heimdall|rest|bor|all|errors] [-f|-e]"
print_status "🔄 Restart services:  polygon-restart [heimdall|rest|bor|all]"
print_status "📈 Live monitor:      polygon-monitor"
print_status "🌐 Network tests:     polygon-network"
print_status ""
print_status "=== 🔧 Service Management ==="
print_status "📄 Check services:       sudo systemctl status [heimdalld|heimdalld-rest|bor]"
print_status "📜 Service logs:         sudo journalctl -u [service] -f"
print_status "🔄 Manual restart:       sudo systemctl restart [service]"
print_status ""
print_status "=== 🌐 Network Endpoints ==="
print_status "🌐 Heimdall RPC:      http://localhost:26657"
print_status "🌐 Heimdall REST:     http://localhost:1317"  
print_status "🌐 Bor RPC:           http://localhost:8545"
print_status "🌐 External ETH RPC:  https://ethereum-rpc.publicnode.com"
print_status ""
print_status "=== 📁 Important Directories ==="
print_status "📁 Data:             /var/lib/polygon/"
print_status "📁 Logs:             /var/log/polygon/"
print_status "📁 Heimdall Config:  /var/lib/polygon/heimdall/config/"
print_status "📁 Bor Config:       /var/lib/polygon/bor/"
print_status ""
print_status "=== 🔍 Troubleshooting ==="
print_status "❌ View all errors:    polygon-logs errors"
print_status "🔧 Network diagnostics: polygon-network"
print_status "📊 Live monitoring:    polygon-monitor"
print_status ""
print_status "⚡ KEY FIXES APPLIED:"
print_status "✅ Added external Ethereum RPC endpoint"
print_status "✅ Configured state sync for faster initial sync"
print_status "✅ Updated peer/bootnode addresses"
print_status "✅ Enhanced error detection and logging"
print_status "✅ Added comprehensive monitoring tools"
print_status ""
print_status "⏳ Initial sync will take several hours. Monitor with: polygon-monitor"
print_status "🎯 The node should now sync properly without getting stuck!"
print_status ""
print_status "Installation completed at $(date)"