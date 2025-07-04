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

## 🚀 Quick Start

### Deploy Infrastructure
```bash
# Deploy complete infrastructure
terraform apply

# Connect to validator node
ssh -i polygon-key ec2-user@<PUBLIC_IP>

# Check service status
sudo systemctl status heimdalld
sudo systemctl status heimdalld-rest
sudo systemctl status bor
```

### Monitor Sync Progress
```bash
# Check Heimdall sync status
curl -s localhost:26657/status | jq '.result.sync_info'

# Check peer connections
curl -s localhost:26657/net_info | jq '.result.n_peers'

# Monitor logs
sudo journalctl -u heimdalld -f
```

## 🏗️ Architecture

### Multi-Layer Design
```
┌─────────────────────────────────────────────────────────────┐
│ Ethereum Mainnet                                            │
│ (Security & Settlement Layer)                               │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          │ Checkpoints & State Commitments
                          │
┌─────────────────────────▼───────────────────────────────────┐
│ Heimdall Layer                                              │
│ (Consensus & Validation)                                    │
│ • Tendermint-based PoS consensus                           │
│ • Validator selection and management                        │
│ • Checkpoint submission to Ethereum                         │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          │ Block Production Coordination
                          │
┌─────────────────────────▼───────────────────────────────────┐
│ Bor Layer                                                   │
│ (Execution & Transaction Processing)                        │
│ • Go-Ethereum fork with custom modifications               │
│ • EVM-compatible transaction execution                      │
│ • Block production and state management                     │
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
- Default peer discovery settings too restrictive

### Solution Implemented
✅ **Working persistent peers** instead of outdated seeds  
✅ **Optimized peer discovery settings** for better connectivity  
✅ **Fresh node identity** to avoid auth conflicts  
✅ **Increased peer limits** for faster sync  
✅ **Complete automation** in install script  

### Working Peer Configuration
```toml
# Heimdall - Working persistent peers (tested 2025-07-03)
persistent_peers = "7f3049e88ac7f820fd86d9120506aaec0dc54b27@34.89.75.187:26656,2d5484feef4257e56ece025633a6ea132d8cadca@35.246.99.203:26656,72a83490309f9f63fdca3a0bef16c290e5cbb09c@35.246.95.65:26656"

# Bor - Working bootnodes (tested 2025-07-03)
bootnodes = [
    "enode://e4fb013061eba9a2c6fb0a41bbd4149f4808f0fb7e88ec55d7163f19a6f02d64d0ce5ecc81528b769ba552a7068057432d44ab5e9e42842aff5b4709aa2c3f3b@34.89.75.187:30303",
    "enode://a49da6300403cf9b31e30502eb22c142ba4f77c9dda44990bccce9f2121c3152487ee95ee55c6b92d4cdce77845e40f59fd927da70ea91cf935b23e262236d75@34.142.43.249:30303",
    "enode://0e50fdcc2106b0c4e4d9ffbd7798ceda9432e680723dc7b7b4627e384078850c1c4a3e67f17ef2c484201ae6ee7c491cbf5e189b8ffee3948252e9bef59fc54e@35.234.148.172:30303",
    "enode://a0bc4dd2b59370d5a375a7ef9ac06cf531571005ae8b2ead2e9aaeb8205168919b169451fb0ef7061e0d80592e6ed0720f559bd1be1c4efb6e6c4381f1bdb986@35.246.99.203:30303"
]
```

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
├── README.md                  # Complete project documentation
├── terraform/
│   ├── main.tf               # Infrastructure automation
│   ├── variables.tf          # Environment configuration
│   ├── install-polygon.sh    # Enhanced automated installation
│   ├── polygon-key           # SSH private key (not in git)
│   └── polygon-key.pub       # SSH public key (not in git)
├── docs/
│   └── troubleshooting.md    # Complete P2P troubleshooting guide
└── .gitignore                # Security and cleanup rules
```

## 🚀 Deployment Guide

### Prerequisites
- AWS CLI configured with appropriate permissions
- Terraform installed
- SSH key pair generated

### Step 1: Deploy Infrastructure
```bash
# Clone repository
git clone <repository-url>
cd polygon-validator-infrastructure/terraform

# Generate SSH key pair
ssh-keygen -t rsa -b 4096 -f polygon-key

# Deploy infrastructure
terraform init
terraform plan
terraform apply
```

### Step 2: Connect and Verify
```bash
# Get public IP
terraform output polygon_node_ip

# Connect to instance
ssh -i polygon-key ec2-user@<PUBLIC_IP>

# Check all services
sudo systemctl status heimdalld
sudo systemctl status heimdalld-rest
sudo systemctl status bor
```

### Step 3: Monitor Progress
```bash
# Check sync status
curl -s localhost:26657/status | jq '.result.sync_info'

# Monitor peer connections
watch -n 10 'curl -s localhost:26657/net_info | jq ".result.n_peers"'

# Follow logs
sudo journalctl -u heimdalld -f
```

## 🔧 Manual Setup (Alternative)

For manual installation without Terraform, see the complete step-by-step guide in `docs/manual-setup.md`.

## 🛠️ Troubleshooting

### Common Issues

1. **P2P Connection Failures**
   ```bash
   # Test connectivity
   nc -zv 34.89.75.187 26656
   
   # Clear cached data
   rm ~/.heimdalld/data/addrbook.json
   
   # Reset node identity
   rm ~/.heimdalld/config/node_key.json
   ```

2. **Service Issues**
   ```bash
   # Check service logs
   sudo journalctl -u heimdalld -n 50
   
   # Restart services
   sudo systemctl restart heimdalld
   sudo systemctl restart bor
   ```

3. **Sync Issues**
   ```bash
   # Check if catching up
   curl -s localhost:26657/status | jq '.result.sync_info.catching_up'
   
   # Monitor block height
   curl -s localhost:26657/status | jq '.result.sync_info.latest_block_height'
   ```

## 🎯 Key Lessons Learned

### Technical Insights
- **Manual testing was essential** for identifying working peers
- **Iterative config updates** helped solve connection issues
- **Source compilation** bypassed dependency conflicts
- **Proper service dependencies** ensure reliable operation

### Automation Priorities
1. **Connectivity testing** before applying configuration
2. **Template-based configs** with working peers as variables
3. **Systematic service creation** with proper dependencies
4. **Automated verification** of setup success

## 🔮 Future Enhancements

### Planned Improvements
- **Multi-Node Setup**: Implement sentry + validator architecture
- **Monitoring Stack**: Grafana/Prometheus integration
- **High Availability**: Load balancing and failover configuration
- **Security Hardening**: Advanced firewall rules and intrusion detection
- **Performance Optimization**: Custom hardware configurations and tuning

### Scaling Considerations
- **Snapshot Integration**: Faster initial sync with trusted snapshots
- **Automated Upgrades**: CI/CD pipeline for node updates
- **Multi-Region Deployment**: Geographic distribution for resilience
- **Backup Strategy**: Automated backup and disaster recovery

## 📚 Resources

### Official Documentation
- [Polygon Validator Documentation](https://docs.polygon.technology/pos/get-started/becoming-a-validator/)
- [Polygon Node Setup Guide](https://docs.polygon.technology/pos/how-to/full-node-deployment/)
- [Bor Documentation](https://docs.polygon.technology/pos/reference/bor/)

### Community Resources
- [Polygon Community Forum](https://forum.polygon.technology/)
- [Polygon Discord](https://discord.gg/polygon)
- [Polygon GitHub](https://github.com/maticnetwork)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests and documentation
5. Submit a pull request

## 📄 License

This project is licensed under the MIT License - see the LICENSE file for details.

## 🙏 Acknowledgments

- Polygon team for comprehensive documentation
- Community contributors for troubleshooting insights
- AWS for reliable cloud infrastructure
- Terraform for infrastructure automation capabilities

---

**Note**: This project demonstrates advanced blockchain infrastructure capabilities highly valued in the Web3 ecosystem. The complete solution includes Infrastructure as Code, security best practices, and production-ready automation.