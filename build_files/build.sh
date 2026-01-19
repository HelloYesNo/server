set -ouex pipefail

### Install packages

# Packages can be installed from any enabled yum repo on the image.
# RPMfusion repos are available by default in ublue main images
# List of rpmfusion packages can be found here:
# https://mirrors.rpmfusion.org/mirrorlist?path=free/fedora/updates/39/x86_64/repoview/index.html&protocol=https&redirect=1

# this installs a package from fedora repos
dnf5 install -y lspci

dnf5 install fedora-workstation-repositories -y
dnf5 config-manager --set-enabled rpmfusion-nonfree-nvidia-driver
dnf5 config-manager --add-repo=https://negativo17.org/repos/fedora-nvidia.repo

#### Example for enabling a System Unit File

systemctl enable podman.socket
