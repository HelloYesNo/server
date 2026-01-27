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

curl -f https://zed.dev/install.sh | sh

#git clone https://github.com/HelloYesNo/coolify.git /var/lib/coolify
#sh /var/lib/coolify/scripts/install.sh

### 3. Filesystem Prep (Coolify & Docker)
# Create the 'dangling' symlink so /data points to writable /var
ln -s /var/lib/coolify /data

### 5. Enable Services
systemctl enable docker
systemctl enable podman.socket
