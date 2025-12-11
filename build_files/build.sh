#!/bin/bash

set -euo pipefail

### Install Docker CE repository
echo "Installing dnf-plugins-core..."
dnf install -y dnf-plugins-core
echo "Adding Docker CE repository..."

# Check if dnf5 is available and use appropriate syntax
if command -v dnf5 >/dev/null 2>&1; then
    echo "Using dnf5 syntax for repository addition..."
    dnf5 config-manager addrepo --from-repofile=https://download.docker.com/linux/fedora/docker-ce.repo --overwrite
else
    echo "Using dnf syntax for repository addition..."
    dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
fi

# Verify repository was added
if [ ! -f /etc/yum.repos.d/docker-ce.repo ]; then
    echo "Downloading Docker CE repository file directly..."
    curl -fsSL -o /etc/yum.repos.d/docker-ce.repo https://download.docker.com/linux/fedora/docker-ce.repo
fi

### Import Docker GPG key
echo "Importing Docker GPG key..."
rpm --import https://download.docker.com/linux/fedora/gpg

### Remove podman-docker to avoid conflicts with docker-ce
echo "Removing podman-docker if present..."
dnf remove -y podman-docker 2>/dev/null || true

### Install all required packages for Coolify
echo "Installing required packages..."
dnf install -y curl wget git jq openssl openssh-server \
               docker-ce docker-ce-cli containerd.io docker-compose-plugin \
               firewalld

### Clean up DNF cache
dnf clean all

### Configure SSH daemon to use writable authorized_keys location
echo "Configuring SSH daemon..."
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/coolify.conf << 'EOF'
# Use writable location for authorized_keys (immutable OS compatible)
AuthorizedKeysFile /var/lib/coolify/ssh/authorized_keys/%u
# Allow root login with key-based authentication
PermitRootLogin prohibit-password
# Disable password authentication
PasswordAuthentication no
EOF

# Enable sshd (but don't start at build time)
systemctl enable sshd

### Set up writable directories for SSH authorized_keys
echo "Creating writable SSH directory structure..."
mkdir -p /var/lib/coolify/ssh/authorized_keys
chmod 755 /var/lib/coolify/ssh
chmod 755 /var/lib/coolify/ssh/authorized_keys

### Generate SSH key pair for Coolify host access
echo "Generating SSH key pair for Coolify..."
mkdir -p /data/coolify/ssh/keys
ssh-keygen -t ed25519 -a 100 -f /data/coolify/ssh/keys/id.root@host.docker.internal -q -N "" -C "coolify-host-access"
chown -R 9999:root /data/coolify

# Add Coolify's public key to authorized_keys location
cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub > /var/lib/coolify/ssh/authorized_keys/root
chmod 644 /var/lib/coolify/ssh/authorized_keys/root

# Also add to /root/.ssh/authorized_keys for backward compatibility (if overlay permits)
if touch /root/.ssh/test 2>/dev/null; then
    mkdir -p /root/.ssh
    cat /data/coolify/ssh/keys/id.root@host.docker.internal.pub >> /root/.ssh/authorized_keys
    chmod 600 /root/.ssh/authorized_keys
    chmod 700 /root/.ssh
    rm -f /root/.ssh/test
    echo "Added Coolify SSH key to /root/.ssh/authorized_keys"
else
    echo "Skipping /root/.ssh (read-only filesystem)"
fi

### Add user's public SSH key
echo "Adding user's public SSH key..."
USER_KEY="ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL/gvaviFLLtZu2tRR6zEeYf4JhHARkuygogQvjnzX/b"
echo "$USER_KEY" >> /var/lib/coolify/ssh/authorized_keys/root
if touch /root/.ssh/test 2>/dev/null; then
    echo "$USER_KEY" >> /root/.ssh/authorized_keys
    rm -f /root/.ssh/test
    echo "User's SSH key added to /root/.ssh/authorized_keys"
else
    echo "User's SSH key added to writable location only (/var/lib/coolify/ssh/authorized_keys/root)"
fi
echo "User's SSH key added successfully."

### Configure Docker daemon
echo "Configuring Docker daemon..."
mkdir -p /etc/docker
cat > /etc/docker/daemon.json << 'EOF'
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "default-address-pools": [
    {"base": "10.0.0.0/8", "size": 24}
  ]
}
EOF

# Enable and start Docker at boot
systemctl enable docker

### Enable firewalld (configuration will be applied at first boot)
echo "Enabling firewalld..."
systemctl enable firewalld

### Pre-download Coolify assets
echo "Downloading Coolify assets..."
mkdir -p /usr/share/coolify
curl -fsSL -L https://cdn.coollabs.io/coolify/docker-compose.yml -o /usr/share/coolify/docker-compose.yml
curl -fsSL -L https://cdn.coollabs.io/coolify/docker-compose.prod.yml -o /usr/share/coolify/docker-compose.prod.yml
curl -fsSL -L https://cdn.coollabs.io/coolify/.env.production -o /usr/share/coolify/.env.production
curl -fsSL -L https://cdn.coollabs.io/coolify/upgrade.sh -o /usr/share/coolify/upgrade.sh
chmod +x /usr/share/coolify/upgrade.sh

### Create data directories with correct permissions
echo "Creating Coolify data directories..."
mkdir -p /data/coolify/{source,ssh,applications,databases,backups,services,proxy,sentinel}
mkdir -p /data/coolify/ssh/{keys,mux}
mkdir -p /data/coolify/proxy/dynamic
chown -R 9999:root /data/coolify
chmod -R 700 /data/coolify

### Create startup script that skips package installation
echo "Creating Coolify startup script..."
cat > /usr/bin/coolify-start << 'EOF'
#!/bin/bash
set -euo pipefail

echo "Starting Coolify setup..."

# Ensure Docker is running
if ! systemctl is-active --quiet docker; then
    echo "Starting Docker daemon..."
    systemctl start docker
fi

# Ensure SSH daemon is running
if ! systemctl is-active --quiet sshd; then
    echo "Starting SSH daemon..."
    systemctl start sshd
fi

# Configure firewall (ensure ports are open)
if ! systemctl is-active --quiet firewalld; then
    echo "Starting firewalld..."
    systemctl start firewalld
fi

# Add firewall rules if not already present
if ! firewall-cmd --list-services --permanent 2>/dev/null | grep -q '\bssh\b'; then
    echo "Adding SSH service to firewall..."
    firewall-cmd --permanent --add-service=ssh
fi

if ! firewall-cmd --list-ports --permanent 2>/dev/null | grep -q '\b8000/tcp\b'; then
    echo "Adding port 8000/tcp to firewall..."
    firewall-cmd --permanent --add-port=8000/tcp
fi

# Reload firewall to apply changes
echo "Reloading firewall..."
firewall-cmd --reload

# Copy Coolify assets if /data/coolify/source is empty
if [ ! -f /data/coolify/source/docker-compose.yml ]; then
    echo "Copying Coolify assets to /data/coolify/source..."
    cp /usr/share/coolify/docker-compose.yml /data/coolify/source/
    cp /usr/share/coolify/docker-compose.prod.yml /data/coolify/source/
    cp /usr/share/coolify/.env.production /data/coolify/source/
    cp /usr/share/coolify/upgrade.sh /data/coolify/source/
    chmod +x /data/coolify/source/upgrade.sh
fi

# Set ownership of /data/coolify
chown -R 9999:root /data/coolify
chmod -R 700 /data/coolify

# Generate environment variables if not present
ENV_FILE="/data/coolify/source/.env"
if [ ! -f "$ENV_FILE" ]; then
    echo "Creating initial .env file..."
    cp /data/coolify/source/.env.production "$ENV_FILE"
    
    # Generate secure secrets
    openssl rand -hex 16 > /tmp/app_id
    openssl rand -base64 32 > /tmp/app_key
    openssl rand -base64 32 > /tmp/db_password
    openssl rand -base64 32 > /tmp/redis_password
    
    sed -i "s|^APP_ID=.*|APP_ID=$(cat /tmp/app_id)|" "$ENV_FILE"
    sed -i "s|^APP_KEY=.*|APP_KEY=base64:$(cat /tmp/app_key)|" "$ENV_FILE"
    sed -i "s|^DB_PASSWORD=.*|DB_PASSWORD=$(cat /tmp/db_password)|" "$ENV_FILE"
    sed -i "s|^REDIS_PASSWORD=.*|REDIS_PASSWORD=$(cat /tmp/redis_password)|" "$ENV_FILE"
    
    rm -f /tmp/app_id /tmp/app_key /tmp/db_password /tmp/redis_password
fi

# Ensure Coolify network exists
if ! docker network inspect coolify >/dev/null 2>&1; then
    echo "Creating Coolify Docker network..."
    if ! docker network create --attachable --ipv6 coolify 2>/dev/null; then
        echo "Failed to create coolify network with ipv6. Trying without ipv6..."
        docker network create --attachable coolify 2>/dev/null
    fi
fi

echo "Starting Coolify containers..."
cd /data/coolify/source
./upgrade.sh

echo ""
echo "================================================"
echo "Coolify setup complete!"
echo ""
echo "Coolify should now be accessible at:"
echo "  http://$(hostname -I | awk '{print $1}'):8000"
echo ""
echo "To check container status: docker ps"
echo "To view logs: docker logs coolify"
echo "================================================"
EOF

### Make script executable
chmod +x /usr/bin/coolify-start

### Create systemd service for auto-start
echo "Creating Coolify auto-start service..."
cat > /etc/systemd/system/coolify-start.service << 'EOF'
[Unit]
Description=Coolify Startup Service
After=docker.service sshd.service network-online.target
Wants=network-online.target
Requires=docker.service

[Service]
Type=oneshot
ExecStart=/usr/bin/coolify-start
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

systemctl enable coolify-start.service

echo "Build completed successfully!"
echo ""
echo "Coolify will automatically start on first boot."
echo "You can also manually run: coolify-start"
