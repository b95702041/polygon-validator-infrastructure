#!/bin/bash
# Enhanced Polygon Validator Installation Script

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
NC='\033[0m'

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_status "Starting Enhanced Polygon Installation"

# Update system with conflict resolution
print_status "Updating system packages"
sudo dnf update -y --allowerasing
sudo dnf groupinstall -y "Development Tools"
sudo dnf install -y wget curl git jq nc

# Install Go
print_status "Installing Go 1.24.4"
cd /tmp
wget -q https://go.dev/dl/go1.24.4.linux-amd64.tar.gz
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf go1.24.4.linux-amd64.tar.gz
echo 'export PATH=$PATH:/usr/local/go/bin' | sudo tee -a /etc/profile
export PATH=$PATH:/usr/local/go/bin
export GOPATH=$HOME/go
export PATH=$PATH:$GOPATH/bin

# Continue with rest of installation...
print_status "System update completed"
