#!/bin/bash

set -euo pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/39/x86_64/repable/index.html&protocol=https&redirect=1

### Setup Coolify directories and files
mkdir -p /data/coolify/{source,ssh,applications,databases,backups,services,proxy,sentinel}
mkdir -p /data/coolify/ssh/{keys,mux}
mkdir -p /data/coolify/proxy/dynamic

### Download Coolify Docker compose files
CDN="https://cdn.coollabs.io/coolify"
curl -fsSL -L $CDN/docker-compose.yml -o /data/coolify/source/docker-compose.yml
curl -fsSL -L $CDN/docker-compose.prod.yml -o /data/coolify/source/docker-compose.prod.yml
curl -fsSL -L $CDN/.env.production -o /data/coolify/source/.env.production
curl -fsSL -L $CDN/upgrade.sh -o /data/coolify/source/upgrade.sh

### Create .env file from .env.production
if [ -f /data/coolify/source/.env.production ]; then
    cp /data/coolify/source/.env.production /data/coolify/source/.env
fi

### Create install script
cat > /usr/bin/coolify-start << 'EOF'
#!/bin/bash
set -e

# Generate random secrets if .env doesn't exist or is empty
if [ ! -f /data/coolify/source/.env ] || [ ! -s /data/coolify/source/.env ]; then
    echo "Generating Coolify configuration..."
    cat > /data/coolify/source/.env << 'CONFIGEOF'
APP_ID=$(openssl rand -hex 16)
APP_KEY=base64:$(openssl rand -base64 32)
DB_PASSWORD=$(openssl rand -base64 32)
REDIS_PASSWORD=$(openssl rand -base64 32)
PUSHER_APP_ID=$(openssl rand -hex 32)
PUSHER_APP_KEY=$(openssl rand -hex 32)
PUSHER_APP_SECRET=$(openssl rand -hex 32)
CONFIGEOF
fi

cd /data/coolify/source
docker compose up -d

EOF

### Make scripts executable
chmod +x /usr/bin/coolify-start

### Set permissions
chown -R 9999:root /data/coolify
chmod -R 700 /data/coolify
