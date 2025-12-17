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
               firewalld just distrobox podman

### Clean up DNF cache
dnf clean all

### Configure SSH daemon to use writable authorized_keys location
echo "Configuring SSH daemon..."
mkdir -p /etc/ssh/sshd_config.d
cat > /etc/ssh/sshd_config.d/coolify.conf << 'EOF'
# Use standard location for authorized_keys (compatible with immutable OS via /root symlink)
AuthorizedKeysFile /root/.ssh/authorized_keys
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
mkdir -p /var/lib/coolify/ssh/{keys,mux}
chmod 755 /var/lib/coolify/ssh

### Set up standard SSH directory for authorized_keys
echo "Setting up SSH authorized_keys..."
mkdir -p /root/.ssh
chmod 700 /root/.ssh
echo "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIL/gvaviFLLtZu2tRR6zEeYf4JhHARkuygogQvjnzX/b" > /root/.ssh/authorized_keys
chmod 600 /root/.ssh/authorized_keys

echo "SSH directories created. SSH host keys will be generated at runtime by sshd."
echo "User SSH key has been added to /root/.ssh/authorized_keys."

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
mkdir -p /var/lib/coolify/{source,ssh/{keys,mux},applications,databases,backups,services,proxy/dynamic,sentinel}
mkdir -p /data

# Create symlink from /data/coolify to writable location (immutable OS compatible)
echo "Creating symlink /data/coolify -> /var/lib/coolify..."
ln -sfn /var/lib/coolify /data/coolify

# Set permissions (will be adjusted after installation)
chown -R 9999:root /var/lib/coolify
chmod -R 700 /data/coolify
chmod 755 /var/lib/coolify/ssh

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

### Set up Coolify Distrobox container
echo "Setting up Coolify Distrobox container..."
# Copy distrobox container definition
mkdir -p /etc/distrobox
cp /ctx/coolify-distrobox.json /etc/distrobox/coolify.json
# Copy container installation script
cp /ctx/install-coolify-container /usr/bin/install-coolify-container
chmod +x /usr/bin/install-coolify-container
# Install systemd service for auto-starting distrobox container
cp /ctx/coolify-distrobox.service /etc/systemd/system/coolify-distrobox.service
systemctl enable coolify-distrobox.service

### Create startup script that skips package installation
echo "Creating Coolify startup script..."
cat > /usr/bin/coolify-start << 'EOF'
#!/bin/bash
set -euo pipefail

echo "=== Coolify Distrobox Management Script ==="
date

# Check if distrobox container exists
if ! distrobox list | grep -q '^coolify\s'; then
    echo "Coolify distrobox container not found."
    echo ""
    echo "To set up Coolify:"
    echo "1. Create and enter distrobox container: distrobox enter coolify"
    echo "2. Inside container, install Coolify: install-coolify-container"
    echo "3. Exit container - Coolify will auto-start on subsequent boots via systemd"
    echo ""
    echo "Exiting cleanly (Coolify container not set up)."
    exit 0
fi

echo "Coolify distrobox container found."
echo "Checking if container is running..."
if distrobox list | grep -q '^coolify\s.*running'; then
    echo "Container is already running."
else
    echo "Starting container..."
    distrobox-start coolify
fi

echo ""
echo "================================================"
echo "Coolify distrobox container management:"
echo ""
echo "Coolify should be accessible at:"
echo "  http://localhost:8000"
echo ""
echo "To enter container: distrobox enter coolify"
echo "To view container status: distrobox list"
echo "To stop container: distrobox-stop coolify"
echo "To restart container: distrobox-stop coolify && distrobox-start coolify"
echo "================================================"
EOF

### Make script executable
chmod +x /usr/bin/coolify-start



echo "Build completed successfully!"
echo ""
echo "Coolify on Universal Blue (Distrobox edition) image created."
echo ""
echo "After booting the system:"
echo "1. SSH into the system (port 2222) using your SSH key"
echo "2. Create and enter Coolify container: distrobox enter coolify"
echo "3. Inside container, install Coolify: install-coolify-container"
echo "4. Exit container - Coolify will auto-start on subsequent boots"
echo ""
echo "You can also manually manage the container: coolify-start"
echo "Or check container status: distrobox list"
