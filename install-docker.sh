#!/usr/bin/env bash
set -e

DOCKER_DESKTOP_URL="https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb"
DOCKER_DEB="docker-desktop-amd64.deb"

# Detect CI environment
if [ "${CI}" = "true" ] || [ "${GITHUB_ACTIONS}" = "true" ]; then
    IN_CI=1
else
    IN_CI=0
fi

# ---------------------------------------------------------
# Helper: Check if Docker is installed
# ---------------------------------------------------------
check_docker_installed() {
    if command -v docker >/dev/null 2>&1; then
        echo "✔ Docker is already installed"
        echo "Version: $(docker --version)"

        if [ "$IN_CI" -eq 0 ]; then
            sudo systemctl status docker --no-pager || true
        else
            echo "ℹ Skipping systemctl (CI mode)"
        fi
        return 0
    fi
    return 1
}

# ---------------------------------------------------------
# Fix/Reinstall: Remove conflicting installs
# ---------------------------------------------------------
fix_existing_install() {
    if [ "$IN_CI" -eq 1 ] || [ "$DRY_RUN" = "1" ]; then
        echo "⏭️  fix mode skipped (CI/DRY_RUN)"
        return 0
    fi

    echo "⚠ Fixing conflicts + removing old Docker installs..."

    # Remove all Docker repos
    sudo rm -f /etc/apt/sources.list.d/docker.list
    sudo rm -f /etc/apt/sources.list.d/docker.sources
    sudo rm -f /etc/apt/sources.list.d/docker-desktop.list

    # Remove all GPG keyrings
    sudo rm -f /etc/apt/keyrings/docker.gpg
    sudo rm -f /etc/apt/keyrings/docker.asc

    # Remove stale trusted.gpg key if present
    sudo apt-key del 7EA0A9C3F273FCD8 2>/dev/null || true
    sudo gpg --batch --yes --delete-key 7EA0A9C3F273FCD8 2>/dev/null || true

    # Remove any conflicting packages
    sudo apt remove -y \
        docker.io docker-doc docker-compose docker-compose-v2 \
        containerd containerd.io podman-docker runc docker-desktop || true

    sudo apt purge -y \
        docker-ce docker-ce-cli docker-buildx-plugin docker-compose-plugin \
        docker-ce-rootless-extras docker-model-plugin || true

    sudo apt autoremove -y
    sudo apt autoclean -y

    echo "✔ Cleanup completed"
}


# ---------------------------------------------------------
# Install Docker Engine (official repo)
# ---------------------------------------------------------
install_docker_default() {
    if [ "$IN_CI" -eq 1 ]; then
        echo "⏭️  install_docker_default skipped (CI mode)"
        return 0
    fi

    echo "⚙ Installing Docker Engine (official repo)..."

    sudo apt update
    sudo apt install -y ca-certificates curl

    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # shellcheck source=/etc/os-release
    source /etc/os-release
    CODENAME="${VERSION_CODENAME:-$UBUNTU_CODENAME}"

    sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: ${CODENAME}
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    sudo apt update

    sudo apt install -y \
        docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin

    sudo systemctl start docker
    sudo systemctl status docker --no-pager || true

    echo "✔ Docker Engine installed successfully"
}

# ---------------------------------------------------------
# Install Docker Desktop (Linux)
# ---------------------------------------------------------
install_docker_desktop() {
    if [ "$IN_CI" -eq 1 ]; then
        echo "⏭️  Docker Desktop install skipped (CI mode)"
        return 0
    fi

    echo "📦 Installing Docker Desktop..."

    # Add Docker's official GPG key:
    sudo apt update
    sudo apt install ca-certificates curl
    sudo install -m 0755 -d /etc/apt/keyrings
    sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    sudo chmod a+r /etc/apt/keyrings/docker.asc

    # Add the repository to Apt sources:
    sudo tee /etc/apt/sources.list.d/docker.sources <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Signed-By: /etc/apt/keyrings/docker.asc
EOF

    sudo apt update

    mkdir -p "$HOME/downloads"

    if [ ! -f "$HOME/downloads/${DOCKER_DEB}" ]; then
        echo "⬇ Downloading Docker Desktop..."
        wget -O "$HOME/downloads/${DOCKER_DEB}" "${DOCKER_DESKTOP_URL}"
    else
        echo "✔ Installer already present"
    fi

    # fix_existing_install

    sudo apt update
    sudo apt install -y "$HOME/downloads/${DOCKER_DEB}"

    echo "Ignore (Docker Installed) - N: Download is performed unsandboxed as root as file '~../../docker-desktop-amd64.deb' couldn't be accessed by user '_apt'. - pkgAcquire::Run (13: Permission denied)"


}

# ---------------------------------------------------------
# Install via convenience script
# ---------------------------------------------------------
install_convenience_script() {
    if [ "$IN_CI" -eq 1 ]; then
        echo "⏭️  Convenience script skipped (CI mode)"
        return 0
    fi

    echo "⚙ Installing using convenience script..."

    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh
}

detect_docker_installation() {
    INSTALLED_APT=$(dpkg -l | grep -E 'docker|containerd|runc' | wc -l)
    BINARY_EXISTS=$(which docker >/dev/null 2>&1 && echo yes || echo no)
    BIN_PACKAGE=$(dpkg -S $(which docker 2>/dev/null) 2>/dev/null | wc -l)

    if [ "$INSTALLED_APT" -gt 0 ]; then
        echo "docker_install_type=apt"
        return
    fi

    if [ "$BINARY_EXISTS" = "yes" ] && [ "$BIN_PACKAGE" -eq 0 ]; then
        echo "docker_install_type=script"
        return
    fi

    if [ "$BINARY_EXISTS" = "yes" ]; then
        echo "docker_install_type=unknown"
        return
    fi

    echo "docker_install_type=none"
}


# ---------------------------------------------------------
# Uninstall Docker completely
# ---------------------------------------------------------
uninstall_docker() {
    echo "🔧 Uninstalling Docker..."

    TYPE=$(detect_docker_installation)

    case "$TYPE" in
        docker_install_type=apt)
            echo "📦 Detected APT installation"
            sudo systemctl stop docker docker.socket containerd || true

            sudo apt-get purge -y \
                docker-ce docker-ce-cli containerd.io containerd \
                docker-buildx-plugin docker-compose-plugin \
                docker-ce-rootless-extras docker-model-plugin

            sudo apt-get autoremove -y
            ;;

        docker_install_type=script)
            echo "📜 Detected convenience script installation"
            sudo systemctl stop docker docker.socket containerd || true

            sudo rm -f /usr/bin/docker /usr/bin/dockerd \
                /usr/bin/containerd /usr/bin/containerd-shim* \
                /usr/local/bin/docker* || true
            ;;

        docker_install_type=unknown)
            echo "⚠ Unknown install type — cleaning everything"
            sudo systemctl stop docker docker.socket containerd || true

            sudo apt-get purge -y docker-ce docker-ce-cli docker.io containerd.io || true
            sudo rm -f /usr/bin/docker /usr/bin/dockerd /usr/bin/containerd || true
            sudo rm -f /usr/local/bin/docker* || true
            ;;

        docker_install_type=none)
            echo "✔ Docker is not installed"
            return 0
            ;;
    esac

    echo "🧹 Cleaning leftovers..."

    sudo rm -rf /var/lib/docker \
                /var/lib/containerd \
                /etc/docker \
                /run/docker \
                /run/docker.sock \
                ~/.docker \
                /usr/local/bin/dockerd-rootless-setuptool.sh \
                /usr/local/bin/rootlesskit \
                /usr/local/bin/vpnkit \
                /tmp/rootless* || true

    # Remove apt repos & keys after uninstall too
    sudo rm -f /etc/apt/sources.list.d/docker.list
    sudo rm -f /etc/apt/sources.list.d/docker.sources
    sudo rm -f /etc/apt/keyrings/docker.gpg
    sudo rm -f /etc/apt/keyrings/docker.asc

    sudo apt-key del 7EA0A9C3F273FCD8 2>/dev/null || true
    sudo gpg --batch --yes --delete-key 7EA0A9C3F273FCD8 2>/dev/null || true

    # Remove docker if still exists
    if command -v docker >/dev/null 2>&1; then
        sudo rm -f "$(command -v docker)"
    fi

    echo "✔ Docker fully removed"
}




# ---------------------------------------------------------
# MAIN LOGIC
# ---------------------------------------------------------
case "$1" in
    "")
        echo "🔍 Checking if Docker is installed..."
        if check_docker_installed; then
            echo "✔ Nothing to do."
            exit 0
        fi
        echo "🚀 Installing default Docker Engine..."
        install_docker_default
        ;;
    uninstall)
        echo "🚨 Uninstall mode selected"
        uninstall_docker "$2"
        ;;
    reinstall)
        fix_existing_install
        install_docker_default
        ;;
    fix)
        fix_existing_install
        ;;
    desktop)
        install_docker_desktop
        ;;
    convenient|script)
        install_convenience_script
        ;;
    *)
        echo "❌ Unknown option: $1"
        echo "Usage:"
        echo "  ./install-docker.sh"
        echo "  ./install-docker.sh fix"
        echo "  ./install-docker.sh reinstall"
        echo "  ./install-docker.sh uninstall [--purge]"
        echo "  ./install-docker.sh desktop"
        echo "  ./install-docker.sh script"
        echo " Apt-repo: https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository"
        echo " Debian: https://docs.docker.com/engine/install/debian/"
        echo " Ubuntu-Linux: https://docs.docker.com/desktop/setup/install/linux/ubuntu/"
        exit 2
        ;;
esac
