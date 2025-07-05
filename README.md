# Polygon Validator Infrastructure

A comprehensive AWS infrastructure setup for Polygon blockchain nodes using Terraform, with complete P2P connection troubleshooting and automation.

## 🎯 Project Overview

This project demonstrates building a production-ready Polygon validator setup, learning the technical components and operational challenges of running blockchain infrastructure. **P2P connectivity issues have been solved** with working peer configurations and complete automation.

## ✅ Current Status

- **Complete AWS infrastructure** deployed with Terraform automation
- **Amazon Linux 2023** with proper security configuration
- **SSH access** with generated key pairs and security groups
- **Built Bor v1.5.5** (114MB binary) from source successfully
- **Built Heimdall v1.0.7** (heimdalld + heimdallcli) from source
- **P2P connections working** - Both layers connecting to peers
- **Rapid sync progress** - Heimdall syncing at 1,000+ blocks/minute
- **Complete service architecture** with systemd services
- **Proper inter-layer communication** between Bor and Heimdall
- **Cross-platform deployment** - Works on Windows, Linux, and macOS

## 🖥️ Operating System Support

This project works on **Windows, Linux, and macOS** with identical commands:

```bash
# Works on all platforms (Windows PowerShell, Linux Bash, macOS Terminal)
git clone https://github.com/b95702041/polygon-validator-infrastructure.git
cd polygon-validator-infrastructure/terraform

# Generate SSH key pair
ssh-keygen -t rsa -b 4096 -f polygon-key

# Deploy infrastructure
terraform init
terraform apply

# Connect to instance
ssh -i polygon-key ec2-user@<PUBLIC_IP>
```

### What Runs Where
- **Your Local Machine**: Only Terraform and Git (any OS)
- **AWS EC2 Instance**: Always Linux (Amazon Linux 2023)
- **Validator Software**: Always runs on Linux in the cloud

### Minor OS Differences (Rarely Needed)
Only if you need to manually manage files:
- **Windows**: `Remove-Item -Recurse -Force`
- **Linux/macOS**: `rm -rf`

**Note**: The validator deployment is identical regardless of your local operating system since everything runs on Linux in AWS.

## 🚀 Quick Start

### Step 1: Prerequisites
- AWS CLI configured with appropriate permissions
- Terraform installed (any OS)
- SSH client available

### Step 2: Deploy Infrastructure
```bash
# For all platforms
terraform apply

# Get instance IP
terraform output polygon_node_ip

# Connect via SSH
ssh -i polygon-key ec2-user@<PUBLIC_IP>
```

### Step 3: Monitor Installation
```bash
# Check installation progress
sudo tail -f /var/log/polygon-bootstrap.log

# Check service status
sudo systemctl status heimdalld
sudo systemctl status heimdalld-rest
sudo systemctl status bor
```

### Step 4: Monitor Sync Progress
```bash
# Check Heimdall sync status
curl -s localhost:26657/status | jq '.result.sync_info'

# Check peer connections
curl -s localhost:26657/net_info | jq '.result.n_peers'

# Run status monitoring script
~/check-polygon-status.sh
```

## 🏗️ Architecture

### Multi-Layer Design
```
┌─────────────────────────────────────────────────────────────┐
│ Ethereum Mainnet (Layer 1)                                 │
│ • Final settlement layer                                    │
│ • Stores checkpoints every ~30 minutes                     │
│ • Ultimate security source                                  │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          │ Checkpoints
                          │
┌─────────────────────────▼───────────────────────────────────┐
│ Heimdall Layer (Consensus/Validation)                      │
│ • Proof of Stake consensus                                  │
│ • Validator selection and management                        │
│ • Checkpoint creation and submission                        │
│ • Decides WHO can create blocks                            │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          │ Block Production Instructions
                          │
┌─────────────────────────▼───────────────────────────────────┐
│ Bor Layer (Execution/Block Production)                     │
│ • Processes transactions                                    │
│ • Creates blocks with transactions                          │
│ • Executes smart contracts                                  │
│ • Handles user interactions                                 │
└─────────────────────────────────────────────────────────────┘
```

### Service Architecture
- **heimdalld.service** - Main consensus daemon
- **heimdalld-rest.service** - REST API server (port 1317)
- **bor.service** - Execution layer daemon
- **Auto-restart** and dependency management

## 🛠️ Technical Implementation

### Infrastructure Components
- **Cloud Provider**: AWS EC2 (t3.medium)
- **Infrastructure as Code**: Terraform
- **Blockchain**: Polygon Bor + Heimdall clients
- **Operating System**: Amazon Linux 2023
- **Development**: Go 1.24.4, Git, Development Tools

### Network Configuration
- **Instance Type**: t3.medium (2 vCPU, 4GB RAM)
- **Storage**: 50GB GP3 SSD for blockchain data
- **Network**: Default VPC with custom security group
- **Estimated Cost**: ~$35/month when running continuously

### Required Open Ports
```hcl
Port 22 (SSH)     - Administrative access
Port 26656 (TCP)  - Heimdall P2P communication
Port 26657 (TCP)  - Heimdall RPC server
Port 30303 (TCP)  - Bor P2P communication
Port 8545 (TCP)   - Bor RPC server
Port 1317 (TCP)   - Heimdall REST API
```

## 🔧 P2P Connection Solution

### Problem Solved
The initial setup faced P2P connection failures due to:
- Empty seeds configuration in Heimdall
- Outdated seed nodes in community documentation
- **Amoy testnet infrastructure limitations** - insufficient active peers
- Default peer discovery settings too restrictive

### Network Migration: Amoy → Mainnet
Initially attempted deployment on **Amoy testnet** but encountered:
- ❌ **Limited peer discovery** - Few active seed nodes
- ❌ **Consensus RPC timeouts** - Testnet infrastructure gaps  
- ❌ **Inconsistent connectivity** - Mumbai testnet deprecated (April 2024)
- ❌ **Auth failures** - Mismatched node identities in testnet seeds

**Solution**: Migrated to **Polygon Mainnet** for:
- ✅ **Robust peer discovery** with hundreds of active nodes
- ✅ **Stable infrastructure** for reliable syncing
- ✅ **Production-ready environment** for complete validator experience
- ✅ **Consistent connectivity** - Well-maintained mainnet infrastructure

### Solution Implemented
✅ **Working persistent peers** instead of outdated seeds  
✅ **Optimized peer discovery settings** for better connectivity  
✅ **Fresh node identity** to avoid auth conflicts  
✅ **Increased peer limits** for faster sync  
✅ **Complete automation** in install script  
✅ **Bootstrap deployment** to overcome AWS user_data limits

### Working Peer Configuration (Updated 2025-07-03)
```toml
# Heimdall - Working persistent peers
persistent_peers = "7f3049e88ac7f820fd86d9120506aaec0dc54b27@34.89.75.187:26656,2d5484feef4257e56ece025633a6ea132d8cadca@35.246.99.203:26656,72a83490309f9f63fdca3a0bef16c290e5cbb09c@35.246.95.65:26656"

# Bor - Working bootnodes
bootnodes = [
    "enode://e4fb013061eba9a2c6fb0a41bbd4149f4808f0fb7e88ec55d7163f19a6f02d64d0ce5ecc81528b769ba552a7068057432d44ab5e9e42842aff5b4709aa2c3f3b@34.89.75.187:30303",
    "enode://a49da6300403cf9b31e30502eb22c142ba4f77c9dda44990bccce9f2121c3152487ee95ee55c6b92d4cdce77845e40f59fd927da70ea91cf935b23e262236d75@34.142.43.249:30303",
    "enode://0e50fdcc2106b0c4e4d9ffbd7798ceda9432e680723dc7b7b4627e384078850c1c4a3e67f17ef2c484201ae6ee7c491cbf5e189b8ffee3948252e9bef59fc54e@35.234.148.172:30303",
    "enode://a0bc4dd2b59370d5a375a7ef9ac06cf531571005ae8b2ead2e9aaeb8205168919b169451fb0ef7061e0d80592e6ed0720f559bd1be1c4efb6e6c4381f1bdb986@35.246.99.203:30303"
]
```

**⚠️ Note**: These peer addresses are hardcoded and tested as of July 2025. If deployment fails due to peer connectivity issues, update the peer lists in `terraform/full-install-polygon.sh` with current working peers from [Polygon Documentation](https://docs.polygon.technology/pos/reference/seed-and-bootnodes/).

## 🔄 Automation Best Practices

### Timeout Handling
All long-running commands should include timeouts:

```bash
timeout 600 go install github.com/0xPolygon/polygon-edge@develop
timeout 300 wget -q https://example.com/file.tar.gz
```

### Error Detection
Scripts should verify each step before proceeding:

```bash
if verify_polygon_binary "/usr/local/bin/polygon-edge"; then
    print_status "✅ Installation successful"
else
    print_error "❌ Installation failed"
    exit 1
fi
```

### Polygon Edge Installation Issues

#### Problem: Binary download failures
**Error:**
```
wget: cannot download polygon-edge binary
404 Not Found
```

**Root Cause:** Pre-built binary URLs may not exist for all versions or platforms.

**Solution:** Use multiple fallback installation strategies:
1. **Go Install** (fastest, most reliable)
2. **Pre-built Binary** (multiple URLs)
3. **Source Build** (slowest but always works)

#### Problem: Go build cache errors
**Error:**
```
build cache is required, but could not be located: GOCACHE is not defined
```

**Solution:** Set Go environment variables before building:

```bash
export GOCACHE=/tmp/go-cache
export GOPATH=/root/go
mkdir -p $GOCACHE $GOPATH
```

#### Problem: Secrets initialization hanging
**Error:** Script hangs at "Initializing node secrets" step

**Root Cause:** Polygon Edge requires explicit `--insecure` flag for local development.

**Solution:** Add `--insecure` flag to secrets initialization:

```bash
sudo -u polygon /usr/local/bin/polygon-edge secrets init --data-dir /var/lib/polygon --insecure
```

**Note:** The `--insecure` flag stores keys locally on filesystem. Avoid in production.

#### Problem: Genesis creation requires reward wallet
**Error:**
```
reward wallet address must be defined
a custom reward token must be defined when native ERC20 token is non-mintable
```

**Root Cause:** Default consensus is `polybft` (Proof of Stake) which requires reward configuration.

**Solution:** Use simpler IBFT consensus for learning/development:

```bash
sudo -u polygon /usr/local/bin/polygon-edge genesis \
    --dir /var/lib/polygon \
    --name "polygon-edge-local" \
    --chain-id 1001 \
    --consensus ibft \
    --ibft-validator-type bls \
    --block-gas-limit 10000000 \
    --block-time 2s \
    --premine 0x85da99c8a7C2C95964c8EfD687E95E632Fc533D6:1000000000000000000000000
```

**Consensus Options:**
- ✅ **IBFT** - Simple, no rewards needed, perfect for learning
- ❌ **PolyBFT** - Complex, requires rewards/staking, production-focused

#### Problem: Genesis file already exists
**Error:**
```
genesis file at path (/var/lib/polygon) already exists
```

**Root Cause:** Previous installation attempts left configuration files that conflict with new genesis creation.

**Solution:** Clean up existing configuration before creating new genesis:

```bash
# Clean up existing files
sudo rm -rf /var/lib/polygon/genesis.json
sudo rm -rf /var/lib/polygon/consensus/
sudo rm -rf /var/lib/polygon/trie/
sudo rm -rf /var/lib/polygon/blockchain/

# Then proceed with secrets and genesis initialization
sudo -u polygon /usr/local/bin/polygon-edge secrets init --data-dir /var/lib/polygon --insecure
sudo -u polygon /usr/local/bin/polygon-edge genesis --dir /var/lib/polygon --consensus ibft
```

#### Problem: curl-minimal conflicts with curl package
**Error:**
```
package curl-minimal conflicts with curl provided by curl
```

**Root Cause:** Amazon Linux 2023 ships with `curl-minimal` by default, which conflicts with the full `curl` package needed for development tools.

**Solution:** Add `--allowerasing` flag to all `dnf install` commands:

```bash
sudo dnf install -y --allowerasing wget curl git jq nc
sudo dnf groupinstall -y --allowerasing "Development Tools"
```

**Why it works:** The `--allowerasing` flag tells dnf to automatically remove conflicting packages and install the requested ones.

### Fallback Strategies
Implement multiple installation methods with graceful fallbacks:
1. Try fastest method first
2. Fall back to alternative methods
3. Fail with clear error message if all methods fail

## 📊 Performance Metrics

### Sync Performance
- **Heimdall Sync Speed**: ~1,000 blocks/minute
- **Initial Sync Time**: 5-10 hours for Heimdall
- **Peer Connections**: 3-10 stable connections per layer
- **Memory Usage**: ~2-4GB RAM during sync

### Success Indicators
✅ **Heimdall**: Peer count > 0, block height increasing  
✅ **Bor**: RPC responding, peers connecting  
✅ **Services**: All running with restart=on-failure  
✅ **REST API**: localhost:1317 responding  
✅ **Inter-layer**: Bor successfully fetching from Heimdall  

## 📁 Project Structure

```
polygon-validator-infrastructure/
├── README.md                     # Complete project documentation
├── terraform/
│   ├── main.tf                  # Infrastructure automation
│   ├── variables.tf             # Environment configuration
│   ├── install-polygon.sh       # Bootstrap script (small)
│   ├── full-install-polygon.sh  # Complete installation script
│   ├── polygon-key              # SSH private key (not in git)
│   └── polygon-key.pub          # SSH public key (not in git)
└── .gitignore                   # Security and cleanup rules
```

## 🚀 Deployment Architecture

### Bootstrap Deployment Pattern
```
1. Terraform Apply
   ↓
2. AWS EC2 Instance Created
   ↓
3. Bootstrap Script Runs (small, in user_data)
   ↓
4. Downloads Full Installer from GitHub
   ↓
5. Executes Complete Installation
   ↓
6. Services Start & Sync Begins
```

### Benefits of This Approach
- **Overcomes AWS 16KB limit** for user_data
- **Maintainable** - Update installer in GitHub, not Terraform
- **Universal** - Works from any platform
- **Traceable** - All installation steps logged
- **Reliable** - Tested automation with P2P fixes

## 🔧 AWS User Data Limitation Solution

### The Challenge
AWS has a **16KB limit** for EC2 user_data scripts. Our complete Polygon validator installation script with P2P fixes exceeds this limit, causing deployment failures.

### Our Bootstrap Solution
We solved this with a two-script approach:

```
📄 install-polygon.sh (Small Bootstrap - <1KB)
├── Fits within AWS 16KB user_data limit
├── Downloads full installer from GitHub
└── Executes complete installation

📄 full-install-polygon.sh (Complete Installer - ~15KB)
├── Contains all P2P connection fixes
├── Complete build and configuration process
├── Stored in GitHub repository
└── Downloaded and executed by bootstrap script
```

### Why This Approach Works
✅ **Overcomes AWS limits** - Bootstrap script is tiny  
✅ **Maintainable** - Update installer in GitHub, not Terraform  
✅ **Universal** - Works from any platform  
✅ **Reliable** - Full installation script is version controlled  
✅ **Traceable** - All steps logged in EC2 instance  

### Alternative Approaches (Not Used)
- ❌ **S3 Storage** - Requires additional AWS resources and permissions
- ❌ **AMI Images** - Hard to maintain and update
- ❌ **Multiple user_data blocks** - Not supported by AWS
- ❌ **Compressed scripts** - Still hit size limits with our full script

### The Bootstrap Process
1. **Terraform** creates EC2 instance with small bootstrap script
2. **Bootstrap script** runs on EC2 startup
3. **Downloads** full installer from your GitHub repository
4. **Executes** complete installation with all P2P fixes
5. **Logs** everything to `/var/log/polygon-bootstrap.log` and `/var/log/polygon-install.log`

### Monitoring Bootstrap Process
```bash
# Connect to EC2 instance
ssh -i polygon-key ec2-user@<PUBLIC_IP>

# Watch bootstrap progress
sudo tail -f /var/log/polygon-bootstrap.log

# Watch full installation progress
sudo tail -f /var/log/polygon-install.log

# Check if downloads completed
ls -la /tmp/polygon-installer.sh
```

## 🛠️ Troubleshooting

### Common Issues by Platform

#### Windows PowerShell
```powershell
# Check files
Get-Content terraform/install-polygon.sh | Select-Object -First 5

# Remove files
Remove-Item -Path docs -Recurse -Force

# View logs
terraform output polygon_node_ip
```

#### Linux/macOS Bash
```bash
# Check files
head -5 terraform/install-polygon.sh

# Remove files
rm -rf docs/

# View logs
terraform output polygon_node_ip
```

#### AWS EC2 Instance (All Platforms)
```bash
# Check installation progress
sudo tail -f /var/log/polygon-bootstrap.log

# Check service status
sudo systemctl status heimdalld
sudo systemctl status heimdalld-rest
sudo systemctl status bor

# Check connectivity
curl -s localhost:26657/status | jq '.result.sync_info'
```

### P2P Connection Issues
1. **Test connectivity**
   ```bash
   nc -zv 34.89.75.187 26656
   ```

2. **Clear cached data**
   ```bash
   rm ~/.heimdalld/data/addrbook.json
   ```

3. **Restart services**
   ```bash
   sudo systemctl restart heimdalld
   sudo systemctl restart bor
   ```

### Service Issues
1. **Check logs**
   ```bash
   sudo journalctl -u heimdalld -n 50
   sudo journalctl -u bor -n 50
   ```

2. **Verify configurations**
   ```bash
   cat ~/.heimdalld/config/config.toml | grep persistent_peers
   cat ~/.bor/config/config.toml | grep bootnodes
   ```

## 🎯 Understanding Polygon Validator Economics

### Full Node vs Validator
```
Your Current Setup (Full Node):
├── Heimdall ✅ Syncing consensus data
├── Bor ✅ Syncing transaction data  
├── Network Role: Supporting the network
└── Earnings: None (but helps decentralization)

To Become Validator:
├── Stake POL tokens (minimum ~1,000-10,000 POL)
├── Apply to validator set (limited to 105 slots)
├── Maintain 99%+ uptime
└── Earnings: 2-4% annual return on staked POL
```

### Validator Roles Explained
- **Heimdall**: "The Boss" - Decides who can create blocks
- **Bor**: "The Worker" - Actually processes transactions
- **Your Full Node**: "The Supporter" - Validates and serves data

### Revenue Streams (For Validators)
- **Block rewards**: 2-4% annual return on staked POL
- **Transaction fees**: Small portion of network fees
- **Checkpoint rewards**: For validating state transitions

## 📚 Resources

### Official Documentation
- [Polygon Validator Documentation](https://docs.polygon.technology/pos/get-started/becoming-a-validator/)
- [Polygon Node Setup Guide](https://docs.polygon.technology/pos/how-to/full-node-deployment/)
- [Polygon Seed and Bootnodes](https://docs.polygon.technology/pos/reference/seed-and-bootnodes/)

### Development Tools
- [Terraform Documentation](https://www.terraform.io/docs)
- [AWS CLI](https://aws.amazon.com/cli/)

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

---

**Note**: This project demonstrates production-ready Polygon validator deployment with automated P2P connection fixes. The complete solution includes Infrastructure as Code, security best practices, and cross-platform compatibility.