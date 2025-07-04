#!/bin/bash
# Bootstrap script - downloads full installer from GitHub

set -e
exec > >(tee /var/log/polygon-bootstrap.log) 2>&1

echo "Starting Polygon validator bootstrap..."
echo "$(date): Downloading full installer from GitHub"

# Download the complete installer
curl -L -o /tmp/polygon-installer.sh "https://raw.githubusercontent.com/b95702041/polygon-validator-infrastructure/main/terraform/full-install-polygon.sh"

chmod +x /tmp/polygon-installer.sh

echo "$(date): Running full installation"
/tmp/polygon-installer.sh

echo "$(date): Bootstrap completed"
