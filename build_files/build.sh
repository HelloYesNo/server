#!/bin/bash
set -ouex pipefail

### 1. Repository Setup
# Add Docker Repo
dnf5 config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo

# Enable COPR repos for your Desktop Environments
dnf5 copr enable swayfx/swayfx -y
dnf5 copr enable solopasha/hyprland -y

### 2. Package Installation
# Combined list: Docker, Coolify deps, and your Desktop apps
dnf5 install -y --allowerasing \
    docker-ce docker-ce-cli containerd.io \
    docker-buildx-plugin docker-compose-plugin \
    openssl jq \
    nvim gh swayfx sway-config-fedora hyprland firefox just

### 3. Filesystem Prep (Coolify & Docker)
# Create the 'dangling' symlink so /data points to writable /var
ln -s /var/lib/coolify /data

# Bake the configuration files into /usr/lib (The permanent backup)
mkdir -p /usr/lib/coolify/source
curl -fsSL https://cdn.coollabs.io/coolify/docker-compose.yml -o /usr/lib/coolify/source/docker-compose.yml
curl -fsSL https://cdn.coollabs.io/coolify/docker-compose.prod.yml -o /usr/lib/coolify/source/docker-compose.prod.yml
curl -fsSL https://cdn.coollabs.io/coolify/.env.production -o /usr/lib/coolify/source/.env

### 4. Initialization Service
# This handles the transition from read-only /usr to writable /var on boot
cat <<EOF > /usr/lib/systemd/system/coolify-init.service
[Unit]
Description=Initialize Coolify on Writable Partition
After=docker.service
Requires=docker.service
ConditionPathExists=!/var/lib/coolify/source/.env

[Service]
Type=oneshot
RemainAfterExit=yes
# Create the directory in /var (activating the /data symlink)
ExecStartPre=/usr/bin/mkdir -p /var/lib/coolify/source
# Copy baked-in configs to the active directory
ExecStartPre=/usr/bin/cp -rn /usr/lib/coolify/source/. /var/lib/coolify/source/
# Generate a unique secret for this install
ExecStart=/usr/bin/bash -c 'sed -i "s|APP_ID=.*|APP_ID=\$(openssl rand -hex 16)|g" /var/lib/coolify/source/.env'
# Launch Coolify containers
ExecStartPost=/usr/bin/docker compose -f /var/lib/coolify/source/docker-compose.yml -f /var/lib/coolify/source/docker-compose.prod.yml up -d

[Install]
WantedBy=multi-user.target
EOF

### 5. Enable Services
systemctl enable docker
systemctl enable coolify-init.service
systemctl enable podman.socket
