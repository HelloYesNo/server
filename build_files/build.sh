#!/bin/bash

set -euo pipefail

### Install curl (needed for Coolify install script)
echo "Installing curl..."
dnf install -y curl

### Install NVIDIA drivers
echo "Installing NVIDIA drivers..."
dnf install -y https://mirrors.rpmfusion.org/free/fedora/rpmfusion-free-release-$(rpm -E %fedora).noarch.rpm https://mirrors.rpmfusion.org/nonfree/fedora/rpmfusion-nonfree-release-$(rpm -E %fedora).noarch.rpm
dnf install -y akmod-nvidia xorg-x11-drv-nvidia-cuda
dnf clean all

### Create startup script that uses Coolify's install script
cat > /usr/bin/coolify-start << 'EOF'
#!/bin/bash
set -e

echo "Starting Coolify installation..."

# Download and run Coolify install script
curl -fsSL https://cdn.coollabs.io/coolify/install.sh | bash

EOF

### Make script executable
chmod +x /usr/bin/coolify-start
