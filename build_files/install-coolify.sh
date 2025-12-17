#!/bin/bash
set -euo pipefail

echo "=== Coolify Installation Script ==="
echo "This script will install Coolify on your immutable OS."
echo ""

# Check if already installed
if [ -f /var/lib/coolify/.installed ]; then
    echo "Coolify is already installed."
    echo "To reinstall, remove the marker file: rm /var/lib/coolify/.installed"
    exit 0
fi

echo "Step 1: Creating writable directories..."
mkdir -p /var/lib/coolify/{source,ssh/{keys,mux},applications,databases,backups,services,proxy/dynamic,sentinel}
mkdir -p /data

echo "Step 2: Creating /data/coolify symlink..."
ln -sfn /var/lib/coolify /data/coolify

echo "Step 3: Generating unique SSH host keys..."
ssh-keygen -t ed25519 -f /var/lib/coolify/ssh/keys/ssh_host_ed25519_key -N "" -q
ssh-keygen -t rsa -b 4096 -f /var/lib/coolify/ssh/keys/ssh_host_rsa_key -N "" -q
chmod 600 /var/lib/coolify/ssh/keys/ssh_host_*
chown root:root /var/lib/coolify/ssh/keys/ssh_host_*

echo "Step 4: Adding your SSH public key for VM access..."
mkdir -p /var/lib/coolify/ssh/authorized_keys
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL/gvaviFLLtZu2tRR6zEeYf4JhHARkuygogQvjnzX/b" > /var/lib/coolify/ssh/authorized_keys/root
chmod 644 /var/lib/coolify/ssh/authorized_keys/root
chown root:root /var/lib/coolify/ssh/authorized_keys/root

echo "Step 5: Downloading latest Coolify assets..."
curl -fsSL -L https://cdn.coollabs.io/coolify/docker-compose.yml -o /var/lib/coolify/source/docker-compose.yml
curl -fsSL -L https://cdn.coollabs.io/coolify/docker-compose.prod.yml -o /var/lib/coolify/source/docker-compose.prod.yml
curl -fsSL -L https://cdn.coollabs.io/coolify/.env.production -o /var/lib/coolify/source/.env.production
curl -fsSL -L https://cdn.coollabs.io/coolify/upgrade.sh -o /var/lib/coolify/source/upgrade.sh
chmod +x /var/lib/coolify/source/upgrade.sh

echo "Step 6: Generating secure secrets..."
ENV_FILE="/var/lib/coolify/source/.env"
cp /var/lib/coolify/source/.env.production "$ENV_FILE"

openssl rand -hex 16 > /tmp/app_id
openssl rand -base64 32 > /tmp/app_key
openssl rand -base64 32 > /tmp/db_password
openssl rand -base64 32 > /tmp/redis_password

sed -i "s|^APP_ID=.*|APP_ID=$(cat /tmp/app_id)|" "$ENV_FILE"
sed -i "s|^APP_KEY=.*|APP_KEY=base64:$(cat /tmp/app_key)|" "$ENV_FILE"
sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$(cat /tmp/db_password)|" "$ENV_FILE"
sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=$(cat /tmp/redis_password)|" "$ENV_FILE"

rm -f /tmp/app_id /tmp/app_key /tmp/db_password /tmp/redis_password

echo "Step 7: Setting correct permissions..."
chown -R 9999:root /var/lib/coolify
chmod -R 700 /data/coolify

echo "Step 8: Starting required services..."
systemctl start docker sshd firewalld

echo "Step 9: Configuring firewall..."
firewall-cmd --add-service=ssh
firewall-cmd --add-port=8000/tcp

echo "Step 10: Creating Coolify Docker network..."
if ! docker network inspect coolify >/dev/null 2>&1; then
    if ! docker network create --attachable --ipv6 coolify 2>/dev/null; then
        echo "Failed to create coolify network with ipv6. Trying without ipv6..."
        docker network create --attachable coolify 2>/dev/null
    fi
fi

echo "Step 11: Starting Coolify containers..."
cd /var/lib/coolify/source
./upgrade.sh

echo "Step 12: Creating installation marker..."
touch /var/lib/coolify/.installed

echo ""
echo "================================================"
echo "Coolify installation complete!"
echo ""
echo "Coolify should now be accessible at:"
echo "  http://$(hostname -I | awk '{print $1}'):8000"
echo ""
echo "To check container status: docker ps"
echo "To view logs: docker logs coolify"
echo ""
echo "Coolify will auto-start on subsequent boots."
echo "================================================"