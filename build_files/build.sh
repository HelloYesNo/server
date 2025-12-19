#!/bin/bash

set -euo pipefail

### Install Docker CE repository
echo "Installing dnf-plugins-core..."
dnf install -y dnf-plugins-core --allowerasing
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
               firewalld just distrobox podman --allowerasing

### Clean up DNF cache
dnf clean all
