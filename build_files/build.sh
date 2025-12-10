#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/39/x86_64/repoview/index.html&protocol=https&redirect=1

# Install Coolify
curl -fsSL https://github.com/HelloYesNo/coolify/tree/v4.x/scripts/install.sh | sudo bash

### Create install script
cat > /usr/bin/coolify-start << 'EOF'
#!/bin/bash
set -e

cd /data/coolify/source
docker compose up -d

EOF

### Make scripts executable
chmod +x /usr/bin/coolify-start
