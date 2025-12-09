#!/bin/bash

set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/39/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos

dnf5 install -y curl

# Docker is already installed as moby-engine in ucore, just ensure docker-compose is available
dnf5 install -y docker-compose

mkdir -p /data/coolify/{source,ssh,applications,databases,backups,services,proxy,webhooks-during-maintenance}
mkdir -p /data/coolify/ssh/{keys,mux}
mkdir -p /data/coolify/proxy/dynamic

ssh-keygen -f /data/coolify/ssh/keys/id.root@host.docker.internal -t ed25519 -N '' -C root@coolify

mkdir -p /var/roothome/.ssh
cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub >> /var/roothome/.ssh/authorized_keys
chmod 600 /var/roothome/.ssh/authorized_keys

curl -fsSL https://cdn.coollabs.io/coolify/docker-compose.yml -o /data/coolify/source/docker-compose.yml
curl -fsSL https://cdn.coollabs.io/coolify/docker-compose.prod.yml -o /data/coolify/source/docker-compose.prod.yml
curl -fsSL https://cdn.coollabs.io/coolify/.env.production -o /data/coolify/source/.env
curl -fsSL https://cdn.coollabs.io/coolify/upgrade.sh -o /data/coolify/source/upgrade.sh

# Create coolify user with UID 9999 if it doesn't exist
if ! getent passwd 9999 > /dev/null; then
    useradd -u 9999 -r -s /sbin/nologin coolify
fi

chown -R 9999:root /data/coolify
chmod -R 700 /data/coolify

# Use a COPR Example:
#
# dnf5 -y copr enable ublue-os/staging
# dnf5 -y install package
# Disable COPRs so they don't end up enabled on the final image:
# dnf5 -y copr disable ublue-os/staging

#### Example for enabling a System Unit File

systemctl enable docker.service

# Create systemd service for Coolify
cat > /etc/systemd/system/coolify.service << 'EOF'
[Unit]
Description=Coolify Container Management
After=docker.service network-online.target
Requires=docker.service network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/usr/local/bin/coolify-start
ExecStop=/usr/local/bin/coolify-stop
StandardOutput=journal
StandardError=journal
TimeoutStartSec=300
TimeoutStopSec=120

[Install]
WantedBy=multi-user.target
EOF

# Create startup script
cat > /usr/local/bin/coolify-start << 'EOF'
#!/bin/bash
# Try docker compose (Docker CLI plugin) first, fall back to docker-compose
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    docker compose --env-file /data/coolify/source/.env -f /data/coolify/source/docker-compose.yml -f /data/coolify/source/docker-compose.prod.yml up -d --pull always --remove-orphans --force-recreate
elif command -v docker-compose &> /dev/null; then
    docker-compose --env-file /data/coolify/source/.env -f /data/coolify/source/docker-compose.yml -f /data/coolify/source/docker-compose.prod.yml up -d --pull always --remove-orphans --force-recreate
else
    echo "Error: Neither 'docker compose' nor 'docker-compose' command found"
    exit 1
fi
EOF

# Create stop script
cat > /usr/local/bin/coolify-stop << 'EOF'
#!/bin/bash
# Try docker compose (Docker CLI plugin) first, fall back to docker-compose
if command -v docker &> /dev/null && docker compose version &> /dev/null; then
    docker compose --env-file /data/coolify/source/.env -f /data/coolify/source/docker-compose.yml -f /data/coolify/source/docker-compose.prod.yml down
elif command -v docker-compose &> /dev/null; then
    docker-compose --env-file /data/coolify/source/.env -f /data/coolify/source/docker-compose.yml -f /data/coolify/source/docker-compose.prod.yml down
else
    echo "Error: Neither 'docker compose' nor 'docker-compose' command found"
    exit 1
fi
EOF

chmod +x /usr/local/bin/coolify-start /usr/local/bin/coolify-stop

# Enable the coolify service
systemctl enable coolify.service
