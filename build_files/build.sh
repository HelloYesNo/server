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
               firewalld just

### Clean up DNF cache
dnf clean all

### Configure SSH daemon to use writable authorized_keys location
echo "Configuring SSH daemon..."
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/coolify.conf << 'EOF'
# Use writable location for authorized_keys (immutable OS compatible)
AuthorizedKeysFile /var/lib/coolify/ssh/authorized_keys/%u
# Use writable location for host keys (immutable OS compatible)
HostKey /var/lib/coolify/ssh/keys/ssh_host_ed25519_key
HostKey /var/lib/coolify/ssh/keys/ssh_host_rsa_key
# Allow root login with key-based authentication
PermitRootLogin prohibit-password
# Disable password authentication
PasswordAuthentication no
EOF

# Enable sshd (but don't start at build time)
systemctl enable sshd

### Set up writable directories for SSH (keys will be generated at runtime)
echo "Creating writable SSH directory structure..."
mkdir -p /var/lib/coolify/ssh/{authorized_keys,keys,mux}
chmod 755 /var/lib/coolify/ssh
chmod 755 /var/lib/coolify/ssh/authorized_keys

echo "SSH directories created. SSH keys will be generated at runtime by install-coolify."
echo "User SSH key will be added at runtime by install-coolify."

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

### Create minimal directory structure for Coolify (assets will be downloaded at runtime)
echo "Creating minimal directory structure for Coolify..."
mkdir -p /var/lib/coolify/{source,ssh/{keys,mux,authorized_keys},applications,databases,backups,services,proxy/dynamic,sentinel}
mkdir -p /data

# Create symlink from /data/coolify to writable location (immutable OS compatible)
echo "Creating symlink /data/coolify -> /var/lib/coolify..."
ln -sfn /var/lib/coolify /data/coolify

# Set permissions (will be adjusted after installation)
chown -R 9999:root /var/lib/coolify
chmod -R 700 /data/coolify
chmod 755 /var/lib/coolify/ssh
chmod 755 /var/lib/coolify/ssh/authorized_keys

echo "Coolify directories created. Assets will be downloaded at runtime by install-coolify."

### Install Coolify installation script
echo "Installing Coolify installation script..."
cp /ctx/install-coolify.sh /usr/bin/install-coolify
chmod +x /usr/bin/install-coolify

### Install Coolify management tools
echo "Installing Coolify management tools..."
cp /ctx/coolify.just /var/lib/coolify/.justfile
cp /ctx/ujust /usr/bin/ujust
chmod +x /usr/bin/ujust

### Create startup script that skips package installation
echo "Creating Coolify startup script..."
cat > /usr/bin/coolify-start << 'EOF'
#!/bin/bash
set -euo pipefail

echo "=== Coolify Startup Script ==="
date

# Check if Coolify is installed
if [ ! -f /var/lib/coolify/.installed ]; then
    echo "Coolify is not installed."
    echo ""
    echo "To install Coolify, run:"
    echo "  install-coolify"
    echo ""
    echo "After installation, use 'ujust' for management (start, stop, logs, etc)."
    echo ""
    echo "This will download Coolify assets, generate SSH keys, and start Coolify."
    echo "Exiting cleanly (Coolify not installed)."
    exit 0
fi

echo "Coolify is installed. Starting services..."

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
    # Wait for firewalld to be ready (max 30 seconds)
    echo "Waiting for firewalld to be ready..."
    for i in {1..30}; do
        if firewall-cmd --state 2>/dev/null; then
            echo "firewalld is ready."
            break
        fi
        sleep 1
    done
fi

# Add firewall rules if not already present (runtime only, immutable OS compatible)
if ! firewall-cmd --list-services 2>/dev/null | grep -q '\bssh\b'; then
    echo "Adding SSH service to firewall (runtime)..."
    firewall-cmd --add-service=ssh
fi

if ! firewall-cmd --list-ports 2>/dev/null | grep -q '\b8000/tcp\b'; then
    echo "Adding port 8000/tcp to firewall (runtime)..."
    firewall-cmd --add-port=8000/tcp
fi

# Ensure /data/coolify symlink exists (immutable OS compatible)
if [ ! -L /data/coolify ]; then
    echo "Creating /data/coolify symlink to /var/lib/coolify..."
    mkdir -p /data
    ln -sfn /var/lib/coolify /data/coolify
fi

# Verify Coolify assets are present
if [ ! -f /data/coolify/source/docker-compose.yml ]; then
    echo "ERROR: Coolify assets not found in /data/coolify/source/"
    echo "Coolify may not be properly installed. Try running: install-coolify"
    exit 1
fi

echo "Coolify assets verified in /data/coolify/source."

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
echo "Coolify startup complete!"
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
echo "Minimal Coolify image created."
echo ""
echo "After booting the system:"
echo "1. SSH into the system (port 2222)"
echo "2. Run 'install-coolify' to download and install Coolify"
echo "3. After installation, use 'ujust' for management (start, stop, logs, etc.)"
echo "4. Coolify will auto-start on subsequent boots"
echo ""
echo "You can also manually run: coolify-start (checks if Coolify is installed)"
