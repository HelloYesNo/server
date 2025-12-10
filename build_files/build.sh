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

### For immutable distros, create SSH config in system location
mkdir -p /etc/ssh/authorized_keys.d/
cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub >> /etc/ssh/authorized_keys.d/coolify
chmod 600 /etc/ssh/authorized_keys.d/coolify

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

# Configure SSH for Coolify
echo "Configuring SSH for Coolify..."

# Create ~/.ssh directory and symlink authorized_keys to system location
sudo mkdir -p ~/.ssh
sudo chmod 700 ~/.ssh
sudo ln -sf /etc/ssh/authorized_keys.d/coolify ~/.ssh/authorized_keys

# Create backup of sshd_config
sudo cp /etc/ssh/sshd_config /etc/ssh/sshd_config.backup

# Add or update AuthorizedKeysFile directive
if grep -q "^AuthorizedKeysFile" /etc/ssh/sshd_config; then
    # Update existing AuthorizedKeysFile line
    sudo sed -i 's|^AuthorizedKeysFile.*|AuthorizedKeysFile .ssh/authorized_keys /etc/ssh/authorized_keys.d/%u|' /etc/ssh/sshd_config
elif grep -q "^#AuthorizedKeysFile" /etc/ssh/sshd_config; then
    # Uncomment and update commented AuthorizedKeysFile line
    sudo sed -i 's|^#AuthorizedKeysFile.*|AuthorizedKeysFile .ssh/authorized_keys /etc/ssh/authorized_keys.d/%u|' /etc/ssh/sshd_config
else
    # Add new AuthorizedKeysFile line
    echo "AuthorizedKeysFile .ssh/authorized_keys /etc/ssh/authorized_keys.d/%u" | sudo tee -a /etc/ssh/sshd_config
fi

# Ensure the authorized_keys.d directory exists
sudo mkdir -p /etc/ssh/authorized_keys.d
sudo chmod 755 /etc/ssh/authorized_keys.d

# Restart SSH service
sudo systemctl restart sshd
echo "SSH configured successfully!"

# Ensure Docker is running
if ! systemctl is-active --quiet docker; then
    echo "Starting Docker service..."
    sudo systemctl start docker
    sudo systemctl enable docker
fi

# Ensure user can access Docker socket
if ! groups $USER | grep -q docker; then
    echo "Adding user to docker group..."
    sudo usermod -aG docker $USER
    echo "Please log out and back in for changes to take effect"
    exit 1
fi

# Create network only if it doesn't exist
if ! docker network ls | grep -q coolify; then
    docker network create --attachable coolify
fi

# Start Coolify
cd /data/coolify/source
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d

EOF

### Make scripts executable
chmod +x /usr/bin/coolify-start

### Set permissions
chown -R 9999:root /data/coolify
chmod -R 700 /data/coolify
