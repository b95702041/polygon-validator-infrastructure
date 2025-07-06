#!/bin/bash
# Polygon PoS (Bor + Heimdall) Validator Installation Script
# This script builds and configures a complete Polygon validator node
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

print_status "🚀 Starting Polygon PoS (Bor + Heimdall) Installation"

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

# Configure Heimdall with working peers
print_status "Configuring Heimdall with working peer connections..."
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
# * goleveldb (github.com/syndtr/goleveldb - most popular choice)
# * cleveldb (uses levigo wrapper)
# * boltdb (uses etcd's fork of bolt - https://github.com/etcd-io/bbolt)
# * rocksdb (uses github.com/tecbot/gorocksdb)
# * badgerdb (uses github.com/dgraph-io/badger)
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
# Default value '[]' disables cors support
# Use '["*"]' to allow any origin
cors_allowed_origins = []

# A list of methods the client is allowed to use with cross-domain requests
cors_allowed_methods = ["HEAD", "GET", "POST", ]

# A list of non simple headers the client is allowed to use with cross-domain requests
cors_allowed_headers = ["Origin", "Accept", "Content-Type", "X-Requested-With", "X-Server-Time", ]

# TCP or UNIX socket address for the gRPC server to listen on
# NOTE: This server only supports /broadcast_tx_commit
grpc_laddr = ""

# Maximum number of simultaneous connections.
# Does not include RPC (HTTP&WebSocket) connections. See max_open_connections
# If you want to accept a larger number than the default, make sure
# you increase your OS limits.
# 0 - unlimited.
# Should be < {ulimit -Sn} - {MaxNumInboundPeers} - {MaxNumOutboundPeers} - {N of wal, db and other open files}
# 1024 - 40 - 10 - 50 = 924 = ~900
grpc_max_open_connections = 900

# Activate unsafe RPC commands like /dial_seeds and /unsafe_flush_mempool
unsafe = false

# Maximum number of simultaneous connections (including WebSocket).
# Does not include gRPC connections. See grpc_max_open_connections
# If you want to accept a larger number than the default, make sure
# you increase your OS limits.
# 0 - unlimited.
# Should be < {ulimit -Sn} - {MaxNumInboundPeers} - {MaxNumOutboundPeers} - {N of wal, db and other open files}
# 1024 - 40 - 10 - 50 = 924 = ~900
max_open_connections = 900

# Maximum number of unique clientIDs that can /subscribe
# If you're using /broadcast_tx_commit, set to the estimated maximum number
# of broadcast_tx_commit calls per block.
max_subscription_clients = 100

# Maximum number of unique queries a given client can /subscribe to
# If you're using GRPC (or Local RPC client) and /broadcast_tx_commit, set to
# the estimated # maximum number of broadcast_tx_commit calls per block.
max_subscriptions_per_client = 5

# How long to wait for a tx to be committed during /broadcast_tx_commit.
# WARNING: Using a value larger than 10s will result in increasing the
# global HTTP write timeout, which applies to all connections and endpoints.
# See https://github.com/tendermint/tendermint/issues/3435
timeout_broadcast_tx_commit = "10s"

# Maximum size of request body, in bytes
max_body_bytes = 1000000

# Maximum size of request header, in bytes
max_header_bytes = 1048576

# The path to a file containing certificate that is used to create the HTTPS server.
# Migth be either absolute path or path related to Tendermint's config directory.
# If the certificate is signed by a certificate authority,
# the certFile should be the concatenation of the server's certificate, any intermediates,
# and the CA's certificate.
# NOTE: both tls_cert_file and tls_key_file must be present for Tendermint to create HTTPS server.
# Otherwise, HTTP server is run.
tls_cert_file = ""

# The path to a file containing matching private key that is used to create the HTTPS server.
# Migth be either absolute path or path related to Tendermint's config directory.
# NOTE: both tls_cert_file and tls_key_file must be present for Tendermint to create HTTPS server.
# Otherwise, HTTP server is run.
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
# If empty, will use the same port as the laddr,
# and will introspect on the listener or use UPnP
# to figure out the address.
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
# Set false for private or local networks
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
#
# Does not work if the peer-exchange reactor is disabled.
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
# This only accounts for raw transactions (e.g. given 1MB transactions and
# max_txs_bytes=5MB, mempool will only accept 5 transactions).
max_txs_bytes = 1073741824

# Size of the cache (used to filter transactions we saw earlier) in transactions
cache_size = 10000

# Do not remove invalid transactions from the cache (default: false)
# Set to true if it's not possible for any invalid transaction to become valid
# again in the future.
keep_invalid_txs_in_cache = false

# Maximum size of a single transaction.
# NOTE: the max size of a tx transmitted over the network is {max_tx_bytes}.
max_tx_bytes = 1048576

# Maximum size of a batch of transactions to send to a peer
# Including space needed by encoding (one varint per transaction).
# XXX: Unused due to https://github.com/tendermint/tendermint/issues/5796
max_batch_bytes = 0

#######################################################
###         State Sync Configuration Options        ###
#######################################################
[statesync]
# State sync rapidly bootstraps a new node by discovering, fetching, and restoring a state machine
# snapshot from peers instead of fetching and replaying historical blocks. Requires some peers in
# the network to take and serve state machine snapshots. State sync is not attempted if the node
# has any local state (LastBlockHeight > 0). The node will have a truncated block history,
# starting from the height of the snapshot.
enable = false

# RPC servers (comma-separated) for light client verification of the synced state machine and
# retrieval of state data for node bootstrapping. Also needs a trusted height and corresponding
# header hash obtained from a trusted source, and a period during which validators can be trusted.
#
# For Cosmos SDK-based chains, trust_period should usually be about 2/3 of the unbonding period (~2
# weeks) during which they can be financially punished (slashed) for misbehavior.
rpc_servers = ""
trust_height = 0
trust_hash = ""
trust_period = "168h0m0s"

# Time to spend discovering snapshots before initiating a restore.
discovery_time = "15s"

# Temporary directory for state sync snapshot chunks, defaults to the OS tempdir (since v0.33.7).
# Will create a new, randomly named directory within, and remove it when done.
temp_dir = ""

# The timeout duration before re-requesting a chunk, possibly from a different
# peer (default: 1 minute).
chunk_request_timeout = "10s"

# The number of concurrent chunk fetchers to run (default: 1).
chunk_fetchers = "4"

#######################################################
###       Fast Sync Configuration Connections       ###
#######################################################
[fastsync]

# Fast Sync version to use:
#   1) "v0" (default) - the legacy fast sync implementation
#   2) "v1" - refactor of v0 version for better testability
#   2) "v2" - complete redesign of v0, optimized for testability & readability
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
#
# The application will set which txs to index. In some cases a node operator will be able
# to decide which txs to index based on configuration set in the application.
#
# Options:
#   1) "null"
#   2) "kv" (default) - the simplest possible indexer, backed by key-value storage (defaults to levelDB; see DBBackend).
# 		- When "kv" is chosen "tx.height" and "tx.hash" will always be indexed.
indexer = "kv"

#######################################################
###       Instrumentation Configuration Options     ###
#######################################################
[instrumentation]

# When true, Prometheus metrics are served under /metrics on
# PrometheusListenAddr.
# Check out the documentation for the list of available metrics.
prometheus = false

# Address to listen for Prometheus collector(s) connections
prometheus_listen_addr = ":26660"

# Maximum number of simultaneous connections.
# If you want to accept a larger number than the default, make sure
# you increase your OS limits.
# 0 - unlimited.
max_open_connections = 3

# Instrumentation namespace
namespace = "tendermint"
HEIMDALL_EOF

# Initialize Bor
print_status "🔧 Configuring Bor..."
sudo -u polygon mkdir -p /var/lib/polygon/bor/keystore

# Download Bor genesis
print_status "Downloading Bor genesis file..."
if ! run_with_timeout 60 "Download Bor genesis" sudo -u polygon wget -q https://raw.githubusercontent.com/maticnetwork/bor/master/builder/files/genesis-mainnet-v1.json -O /var/lib/polygon/bor/genesis.json; then
    print_error "Failed to download Bor genesis file"
    exit 1
fi

# Note: Bor v1.5.5+ does not require genesis initialization
# The genesis file is loaded directly when the server starts
print_status "✅ Bor configuration completed (genesis initialization not required for v1.5.5+)"

# Configure Bor with working bootnodes
print_status "Configuring Bor with working bootnode connections..."
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
      "enode://e4fb013061eba9a2c6fb0a41bbd4149f4808f0fb7e88ec55d7163f19a6f02d64d0ce5ecc81528b769ba552a7068057432d44ab5e9e42842aff5b4709aa2c3f3b@34.89.75.187:30303",
      "enode://a49da6300403cf9b31e30502eb22c142ba4f77c9dda44990bccce9f2121c3152487ee95ee55c6b92d4cdce77845e40f59fd927da70ea91cf935b23e262236d75@34.142.43.249:30303",
      "enode://0e50fdcc2106b0c4e4d9ffbd7798ceda9432e680723dc7b7b4627e384078850c1c4a3e67f17ef2c484201ae6ee7c491cbf5e189b8ffee3948252e9bef59fc54e@35.234.148.172:30303",
      "enode://a0bc4dd2b59370d5a375a7ef9ac06cf531571005ae8b2ead2e9aaeb8205168919b169451fb0ef7061e0d80592e6ed0720f559bd1be1c4efb6e6c4381f1bdb986@35.246.99.203:30303"
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

# Heimdall service
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
ExecStart=/usr/local/bin/heimdalld start --home /var/lib/polygon/heimdall
StandardOutput=append:/var/log/polygon/heimdalld.log
StandardError=append:/var/log/polygon/heimdalld-error.log
SyslogIdentifier=heimdalld

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
ExecStart=/usr/local/bin/heimdallcli rest-server --home /var/lib/polygon/heimdall --node tcp://127.0.0.1:26657
StandardOutput=append:/var/log/polygon/heimdall-rest.log
StandardError=append:/var/log/polygon/heimdall-rest-error.log
SyslogIdentifier=heimdall-rest

[Install]
WantedBy=multi-user.target
HEIMDALL_REST_SERVICE_EOF

# Bor service
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

# Main status script
print_status "Creating polygon-status utility script..."
sudo tee /usr/local/bin/polygon-status > /dev/null <<'STATUS_SCRIPT_EOF'
#!/bin/bash
echo "=== Polygon PoS Node Status ==="
echo ""

echo "--- Service Status ---"
sudo systemctl status heimdalld --no-pager -l | head -10
echo ""
sudo systemctl status heimdalld-rest --no-pager -l | head -10
echo ""
sudo systemctl status bor --no-pager -l | head -10
echo ""

echo "--- Heimdall Sync Status ---"
curl -s localhost:26657/status | jq '.result.sync_info' 2>/dev/null || echo "Heimdall RPC not ready"
echo ""

echo "--- Heimdall Peers ---"
curl -s localhost:26657/net_info | jq '.result.n_peers' 2>/dev/null || echo "Heimdall RPC not ready"
echo ""

echo "--- Bor Sync Status ---"
curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_syncing","params":[],"id":1}' \
    http://localhost:8545 2>/dev/null | jq . || echo "Bor RPC not ready"
echo ""

echo "--- Latest Block ---"
curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
    http://localhost:8545 2>/dev/null | jq . || echo "Bor RPC not ready"
echo ""

echo "--- Peer Count ---"
curl -s -X POST -H "Content-Type: application/json" \
    --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' \
    http://localhost:8545 2>/dev/null | jq . || echo "Bor RPC not ready"
STATUS_SCRIPT_EOF

# Individual log viewers
print_status "Creating polygon-logs utility script..."
sudo tee /usr/local/bin/polygon-logs > /dev/null <<'LOGS_SCRIPT_EOF'
#!/bin/bash
case "$1" in
    "heimdall"|"h")
        if [ "$2" = "-f" ] || [ "$2" = "follow" ]; then
            tail -f /var/log/polygon/heimdalld.log
        else
            tail -n 100 /var/log/polygon/heimdalld.log
        fi
        ;;
    "rest"|"r")
        if [ "$2" = "-f" ] || [ "$2" = "follow" ]; then
            tail -f /var/log/polygon/heimdall-rest.log
        else
            tail -n 100 /var/log/polygon/heimdall-rest.log
        fi
        ;;
    "bor"|"b")
        if [ "$2" = "-f" ] || [ "$2" = "follow" ]; then
            tail -f /var/log/polygon/bor.log
        else
            tail -n 100 /var/log/polygon/bor.log
        fi
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
        echo "Usage: polygon-logs [heimdall|rest|bor|all] [-f|follow]"
        echo "Examples:"
        echo "  polygon-logs heimdall      # Show last 100 heimdall log lines"
        echo "  polygon-logs heimdall -f   # Follow heimdall logs"
        echo "  polygon-logs bor follow    # Follow bor logs"
        echo "  polygon-logs all           # Show recent logs from all services"
        ;;
esac
LOGS_SCRIPT_EOF

# Restart script
print_status "Creating polygon-restart utility script..."
sudo tee /usr/local/bin/polygon-restart > /dev/null <<'RESTART_SCRIPT_EOF'
#!/bin/bash
case "$1" in
    "heimdall"|"h")
        echo "Restarting Heimdall..."
        sudo systemctl restart heimdalld
        sleep 3
        sudo systemctl status heimdalld --no-pager
        ;;
    "rest"|"r")
        echo "Restarting Heimdall REST..."
        sudo systemctl restart heimdalld-rest
        sleep 3
        sudo systemctl status heimdalld-rest --no-pager
        ;;
    "bor"|"b")
        echo "Restarting Bor..."
        sudo systemctl restart bor
        sleep 3
        sudo systemctl status bor --no-pager
        ;;
    "all"|"a"|"")
        echo "Restarting all Polygon services..."
        sudo systemctl restart heimdalld
        sleep 5
        sudo systemctl restart heimdalld-rest
        sleep 5
        sudo systemctl restart bor
        sleep 5
        echo ""
        echo "=== Service Status ==="
        sudo systemctl status heimdalld --no-pager | head -5
        sudo systemctl status heimdalld-rest --no-pager | head -5
        sudo systemctl status bor --no-pager | head -5
        ;;
    *)
        echo "Usage: polygon-restart [heimdall|rest|bor|all]"
        echo "Examples:"
        echo "  polygon-restart all        # Restart all services"
        echo "  polygon-restart heimdall   # Restart only heimdall"
        echo "  polygon-restart bor        # Restart only bor"
        ;;
esac
RESTART_SCRIPT_EOF

# Performance monitoring script
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
    
    # Service status
    echo "--- Services ---"
    printf "Heimdall:     "
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
    
    printf "Bor:          "
    if systemctl is-active --quiet bor; then
        echo -e "\033[32mRunning\033[0m"
    else
        echo -e "\033[31mStopped\033[0m"
    fi
    echo ""
    
    # Sync status
    echo "--- Sync Status ---"
    heimdall_status=$(curl -s localhost:26657/status 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "Heimdall Latest Block: $(echo $heimdall_status | jq -r '.result.sync_info.latest_block_height' 2>/dev/null || echo 'N/A')"
        echo "Heimdall Catching Up:  $(echo $heimdall_status | jq -r '.result.sync_info.catching_up' 2>/dev/null || echo 'N/A')"
    else
        echo "Heimdall: RPC not ready"
    fi
    
    bor_block=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' http://localhost:8545 2>/dev/null)
    if [ $? -eq 0 ]; then
        echo "Bor Latest Block:      $(echo $bor_block | jq -r '.result' 2>/dev/null || echo 'N/A')"
    else
        echo "Bor: RPC not ready"
    fi
    echo ""
    
    # Peer counts
    echo "--- Peer Connections ---"
    heimdall_peers=$(curl -s localhost:26657/net_info 2>/dev/null | jq -r '.result.n_peers' 2>/dev/null)
    echo "Heimdall Peers: ${heimdall_peers:-'N/A'}"
    
    bor_peers=$(curl -s -X POST -H "Content-Type: application/json" --data '{"jsonrpc":"2.0","method":"net_peerCount","params":[],"id":1}' http://localhost:8545 2>/dev/null | jq -r '.result' 2>/dev/null)
    echo "Bor Peers:      ${bor_peers:-'N/A'}"
    echo ""
    
    # System resources
    echo "--- System Resources ---"
    echo "CPU Usage:     $(top -bn1 | grep "Cpu(s)" | awk '{print $2}' | cut -d'%' -f1)%"
    echo "Memory Usage:  $(free | grep Mem | awk '{printf "%.1f%%", $3/$2 * 100.0}')"
    echo "Disk Usage:    $(df /var/lib/polygon | tail -1 | awk '{print $5}')"
    
    sleep 10
done
MONITOR_SCRIPT_EOF

# Make all scripts executable
print_status "Making utility scripts executable..."
sudo chmod +x /usr/local/bin/polygon-status
sudo chmod +x /usr/local/bin/polygon-logs
sudo chmod +x /usr/local/bin/polygon-restart
sudo chmod +x /usr/local/bin/polygon-monitor
print_status "✅ Utility scripts created and made executable"

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
        systemctl reload heimdalld heimdalld-rest bor
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
fi

# Enable and start services
print_status "🚀 Starting Polygon PoS services..."
sudo systemctl daemon-reload

# Start services in order
sudo systemctl enable heimdalld
sudo systemctl start heimdalld
print_status "Heimdall started, waiting for initialization..."
sleep 15

sudo systemctl enable heimdalld-rest
sudo systemctl start heimdalld-rest
print_status "Heimdall REST started, waiting for initialization..."
sleep 10

sudo systemctl enable bor
sudo systemctl start bor
print_status "Bor started, waiting for initialization..."
sleep 20

# Final status check
print_status "🔍 Checking service status..."
if systemctl is-active --quiet heimdalld; then
    print_status "✅ Heimdall is running"
else
    print_warning "⚠️  Heimdall may still be starting"
fi

if systemctl is-active --quiet heimdalld-rest; then
    print_status "✅ Heimdall REST is running"
else
    print_warning "⚠️  Heimdall REST may still be starting"
fi

if systemctl is-active --quiet bor; then
    print_status "✅ Bor is running"
else
    print_warning "⚠️  Bor may still be starting"
fi

print_status "🎉 Polygon PoS installation completed!"
print_status ""
print_status "=== Quick Commands ==="
print_status "📊 Node status:     polygon-status"
print_status "📋 View logs:       polygon-logs [heimdall|rest|bor|all] [-f]"
print_status "🔄 Restart services: polygon-restart [heimdall|rest|bor|all]"
print_status "📈 Live monitor:    polygon-monitor"
print_status ""
print_status "=== Service Management ==="
print_status "📄 Check individual service: sudo systemctl status [heimdalld|heimdalld-rest|bor]"
print_status "📜 View service logs:        sudo journalctl -u [heimdalld|heimdalld-rest|bor] -f"
print_status ""
print_status "=== Network Endpoints ==="
print_status "🌐 Heimdall RPC:    http://localhost:26657"
print_status "🌐 Heimdall REST:   http://localhost:1317"
print_status "🌐 Bor RPC:         http://localhost:8545"
print_status ""
print_status "=== Important Directories ==="
print_status "📁 Data:      /var/lib/polygon/"
print_status "📁 Logs:      /var/log/polygon/"
print_status "📁 Config:    /var/lib/polygon/heimdall/config/ and /var/lib/polygon/bor/"
print_status ""
print_status "⏳ Initial sync will take several hours. Monitor progress with: polygon-monitor"
print_status ""
print_status "Installation completed at $(date)"