#!/bin/bash
set -e

echo "Fixing Coolify permissions..."

# Ensure /data/coolify directory exists
if [ ! -d "/data/coolify" ]; then
    echo "Creating /data/coolify directory..."
    mkdir -p /data/coolify
fi

# Create all necessary Coolify directories
mkdir -p /data/coolify/{source,ssh,applications,databases,backups,services,proxy,sentinel,webhooks-during-maintenance}
mkdir -p /data/coolify/ssh/{keys,mux}
mkdir -p /data/coolify/proxy/dynamic

# Set ownership to UID 9999 (Coolify's user)
chown -R 9999:root /data/coolify

# Set permissions
# Directories: 755 (read+execute for everyone, write for owner)
# Files: 644 (read for everyone, write for owner)
find /data/coolify -type d -exec chmod 755 {} \;
find /data/coolify -type f -exec chmod 644 {} \;

# Special permissions for SSH directories (more restrictive)
chmod 700 /data/coolify/ssh
chmod 700 /data/coolify/ssh/keys
chmod 700 /data/coolify/ssh/mux

# Ensure SSH keys have correct permissions if they exist
if [ -f "/data/coolify/ssh/keys/id.root@host.docker.internal" ]; then
    chmod 600 /data/coolify/ssh/keys/id.root@host.docker.internal
fi
if [ -f "/data/coolify/ssh/keys/id.root@host.docker.internal.pub" ]; then
    chmod 644 /data/coolify/ssh/keys/id.root@host.docker.internal.pub
fi

echo "Coolify permissions fixed successfully."

# If running as entrypoint, start Coolify
if [ "$1" = "start-coolify" ]; then
    echo "Starting Coolify..."
    exec /usr/bin/coolify-start
fi