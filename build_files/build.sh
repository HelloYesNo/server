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

### Generate an SSH key for Coolify to manage your server
ssh-keygen -f /data/coolify/ssh/keys/id.root@host.docker.internal -t ed25519 -N '' -C root@coolify

### Create .ssh directory in the actual root home location
mkdir -p /var/roothome/.ssh
cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub >> /var/roothome/.ssh/authorized_keys
chmod 600 /var/roothome/.ssh/authorized_keys

### Download Coolify Docker compose files
CDN="https://cdn.coollabs.io/coolify"
curl -fsSL -L $CDN/docker-compose.yml -o /data/coolify/source/docker-compose.yml
curl -fsSL -L $CDN/docker-compose.prod.yml -o /data/coolify/source/docker-compose.prod.yml
curl -fsSL -L $CDN/.env.production -o /data/coolify/source/.env.production
curl -fsSL -L $CDN/upgrade.sh -o /data/coolify/source/upgrade.sh


# Set the correct permissions for the Coolify files and directories
chown -R 9999:root /data/coolify
chmod -R 700 /data/coolify

### Create .env file with generated values during build
if [ -f /data/coolify/source/.env.production ]; then
    # Generate random values during build
    APP_ID=$(openssl rand -hex 16)
    APP_KEY="base64:$(openssl rand -base64 32)"
    DB_PASSWORD=$(openssl rand -base64 32)
    REDIS_PASSWORD=$(openssl rand -base64 32)
    PUSHER_APP_ID=$(openssl rand -hex 32)
    PUSHER_APP_KEY=$(openssl rand -hex 32)
    PUSHER_APP_SECRET=$(openssl rand -hex 32)

    # Create .env file with generated values
    cat > /data/coolify/source/.env << EOF
APP_NAME=Coolify
APP_ID=$APP_ID
APP_KEY=$APP_KEY
APP_ENV=production
APP_PORT=8000


DB_CONNECTION=pgsql
DB_HOST=postgres
DB_PORT=5432
DB_USERNAME=coolify
DB_DATABASE=coolify
DB_PASSWORD=$DB_PASSWORD
REDIS_PASSWORD=$REDIS_PASSWORD
PUSHER_APP_ID=$PUSHER_APP_ID
PUSHER_APP_KEY=$PUSHER_APP_KEY
PUSHER_APP_SECRET=$PUSHER_APP_SECRET

ROOT_USERNAME=
ROOT_USER_EMAIL=
ROOT_USER_PASSWORD=

REGISTRY_URL=ghcr.io
LATEST_IMAGE=latest
SOKETI_PORT=6001
SOKETI_DEBUG=false

PHP_MEMORY_LIMIT=256M
PHP_FPM_PM_CONTROL=dynamic
PHP_FPM_PM_START_SERVERS=1
PHP_FPM_PM_MIN_SPARE_SERVERS=1
PHP_FPM_PM_MAX_SPARE_SERVERS=10

EOF
fi

### Create install script
cat > /usr/bin/coolify-start << 'EOF'
#!/bin/bash
set -e

docker network create --attachable coolify

cd /data/coolify/source
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

EOF

### Make scripts executable
chmod +x /usr/bin/coolify-start

### Set permissions
chown -R 9999:root /data/coolify
chmod -R 700 /data/coolify
