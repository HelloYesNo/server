# Coolify management commands for Universal Blue
# This justfile is installed at /var/lib/coolify/.justfile
# Use via: ujust <command>

[private]
default:
    @echo "Coolify management commands (run inside distrobox container)"
    @echo ""
    @echo "Use 'distrobox enter coolify' to enter container, then run:"
    @echo ""
    @echo "Available commands:"
    @echo "  ujust install        - Install Coolify (download assets, generate secrets)"
    @echo "  ujust start          - Start Coolify containers"
    @echo "  ujust stop           - Stop Coolify containers"
    @echo "  ujust restart        - Restart Coolify containers"
    @echo "  ujust status         - Show Coolify container status"
    @echo "  ujust logs           - Follow Coolify container logs"
    @echo "  ujust upgrade        - Upgrade Coolify to latest version"
    @echo "  ujust backup         - Backup Coolify data to /var/lib/coolify/backups/"
    @echo "  ujust restore <file> - Restore Coolify from backup"
    @echo ""
    @echo "Host management:"
    @echo "  coolify-start        - Check/start Coolify distrobox container (from host)"
    @echo "  distrobox list       - View container status"
    @echo "  distrobox enter coolify - Enter container shell"
    @echo ""
    @echo "For more details, see: https://coolify.io/docs"

# Install Coolify (download assets, generate SSH keys, start containers)
install:
    #!/usr/bin/bash
    set -euo pipefail
    echo "Running Coolify installation inside container..."
    install-coolify-container

# Start Coolify containers
start:
    #!/usr/bin/bash
    set -euo pipefail
    echo "Starting Coolify containers..."
    cd /var/lib/coolify/source
    docker compose up -d

# Stop Coolify containers
stop:
    #!/usr/bin/bash
    set -euo pipefail
    echo "Stopping Coolify containers..."
    cd /var/lib/coolify/source
    docker compose down

# Restart Coolify containers
restart: stop && start

# Show Coolify container status
status:
    #!/usr/bin/bash
    set -euo pipefail
    echo "Coolify container status:"
    docker ps --filter name=coolify

# Follow Coolify container logs
logs:
    #!/usr/bin/bash
    set -euo pipefail
    echo "Following Coolify container logs (Ctrl+C to exit)..."
    cd /var/lib/coolify/source
    docker compose logs -f

# Upgrade Coolify to latest version
upgrade:
    #!/usr/bin/bash
    set -euo pipefail
    echo "Upgrading Coolify to latest version..."
    cd /var/lib/coolify/source
    ./upgrade.sh

# Backup Coolify data
backup:
    #!/usr/bin/bash
    set -euo pipefail
    BACKUP_DIR="/var/lib/coolify/backups"
    BACKUP_FILE="coolify-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    echo "Backing up Coolify data to ${BACKUP_DIR}/${BACKUP_FILE}..."
    mkdir -p "$BACKUP_DIR"
    tar -czf "$BACKUP_DIR/$BACKUP_FILE" \
        -C /var/lib/coolify \
        --exclude="backups" \
        --exclude="source" \
        applications databases services sentinel proxy/dynamic
    echo "Backup created: $BACKUP_FILE"
    echo "Size: $(du -h "$BACKUP_DIR/$BACKUP_FILE" | cut -f1)"

# Restore Coolify from backup
restore file:
    #!/usr/bin/bash
    set -euo pipefail
    BACKUP_DIR="/var/lib/coolify/backups"
    BACKUP_PATH="$BACKUP_DIR/{{ file }}"
    if [ ! -f "$BACKUP_PATH" ]; then
        echo "Error: Backup file not found: {{ file }}"
        echo "Available backups:"
        ls -la "$BACKUP_DIR/"*.tar.gz 2>/dev/null || echo "No backups found"
        exit 1
    fi
    echo "Stopping Coolify containers before restore..."
    cd /var/lib/coolify/source
    docker compose down || true
    echo "Restoring from $BACKUP_PATH..."
    tar -xzf "$BACKUP_PATH" -C /var/lib/coolify
    echo "Restore complete. Start Coolify with: ujust start"

# Show SSH host key fingerprints
ssh-keys:
    #!/usr/bin/bash
    set -euo pipefail
    echo "SSH host key fingerprints:"
    echo "ED25519:"
    ssh-keygen -lf /var/lib/coolify/ssh/keys/ssh_host_ed25519_key
    echo ""
    echo "RSA:"
    ssh-keygen -lf /var/lib/coolify/ssh/keys/ssh_host_rsa_key

# View coolify-distrobox.service logs
service-log:
    #!/usr/bin/bash
    set -euo pipefail
    journalctl -u coolify-distrobox.service -f

# Start coolify-distrobox.service
service-start:
    #!/usr/bin/bash
    set -euo pipefail
    systemctl start coolify-distrobox.service

# Stop coolify-distrobox.service
service-stop:
    #!/usr/bin/bash
    set -euo pipefail
    systemctl stop coolify-distrobox.service

# Restart coolify-distrobox.service
service-restart:
    #!/usr/bin/bash
    set -euo pipefail
    systemctl restart coolify-distrobox.service
