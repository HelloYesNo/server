set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/39/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos
# dnf5 -y install 'dnf5-command(config-manager)'
dnf5 config-manager addrepo --from-repofile https://download.docker.com/linux/fedora/docker-ce.repo

dnf5 install -y --allowerasing docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

dnf5 copr enable swayfx/swayfx -y
dnf5 copr enable solopasha/hyprland -y
dnf5 install -y nvim gh swayfx sway-config-fedora hyprland firefox just

mkdir -p /var/lib/coolify
ln -s /var/lib/coolify /data

#### Example for enabling a System Unit File

systemctl enable podman.socket
