#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/39/x86_64/repoview/index.html&protocol=https&redirect=1

dnf5 install -y curl docker-compose

### Create Coolify directories
mkdir -p /data/coolify/{source,ssh,applications,databases,backups,services,proxy,webhooks-during-maintenance}
mkdir -p /data/coolify/ssh/{keys,mux}
mkdir -p /data/coolify/proxy/dynamic

### Generate SSH key for Coolify
ssh-keygen -f /data/coolify/ssh/keys/id.root@host.docker.internal -t ed25519 -N '' -C root@coolify

### Add SSH key to root authorized_keys
mkdir -p /var/roothome/.ssh
cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub >> /var/roothome/.ssh/authorized_keys
chmod 600 /var/roothome/.ssh/authorized_keys

### Download Coolify files
curl -fsSL https://cdn.coollabs.io/coolify/docker-compose.yml -o /data/coolify/source/docker-compose.yml
curl -fsSL https://cdn.coollabs.io/coolify/docker-compose.prod.yml -o /data/coolify/source/docker-compose.prod.yml

### Create minimal .env template (empty passwords for first-time setup)
cat > /data/coolify/source/.env << 'EOF'
APP_ID=1
APP_NAME=Coolify
APP_KEY=

DB_USERNAME=coolify
DB_PASSWORD=
DB_DATABASE=coolify

REDIS_PASSWORD=

PUSHER_APP_ID=
PUSHER_APP_KEY=
PUSHER_APP_SECRET=

ROOT_USERNAME=
ROOT_USER_EMAIL=
ROOT_USER_PASSWORD=

REGISTRY_URL=ghcr.io
APP_PORT=8000
SOKETI_PORT=6001
APP_ENV=production
EOF

### Set permissions
chown -R 9999:root /data/coolify
chmod -R 700 /data/coolify

### Enable Docker service
systemctl enable docker.service

### Create systemd service
cat > /etc/systemd/system/coolify.service << 'EOF'
[Unit]
Description=Coolify Container Management
After=docker.service network-online.target
Requires=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/bin/coolify-start
ExecStop=/usr/bin/coolify-stop
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

### Create startup script
cat > /usr/bin/coolify-start << 'EOF'
#!/bin/bash
set -e

cd /data/coolify/source

# Generate required passwords if empty
if [ -z "$(grep '^DB_PASSWORD=' .env | cut -d= -f2)" ]; then
    DB_PASS=$(openssl rand -base64 24 | tr -d '/+=')
    sed -i "s/^DB_PASSWORD=.*/DB_PASSWORD=${DB_PASS}/" .env
fi

if [ -z "$(grep '^REDIS_PASSWORD=' .env | cut -d= -f2)" ]; then
    REDIS_PASS=$(openssl rand -base64 24 | tr -d '/+=')
    sed -i "s/^REDIS_PASSWORD=.*/REDIS_PASSWORD=${REDIS_PASS}/" .env
fi

if [ -z "$(grep '^APP_KEY=' .env | cut -d= -f2)" ]; then
    APP_KEY="base64:$(openssl rand -base64 32)"
    sed -i "s/^APP_KEY=.*/APP_KEY=${APP_KEY}/" .env
fi

# Start containers
docker compose --env-file .env -f docker-compose.yml -f docker-compose.prod.yml up -d
EOF

### Create stop script
cat > /usr/bin/coolify-stop << 'EOF'
#!/bin/bash
set -e

cd /data/coolify/source
docker compose --env-file .env -f docker-compose.yml -f docker-compose.prod.yml down
EOF

### Make scripts executable
chmod +x /usr/bin/coolify-start /usr/bin/coolify-stop

### Enable Coolify service
systemctl enable coolify.service