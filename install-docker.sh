#!/usr/bin/env bash
set -e

DOCKER_DESKTOP_URL="https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb"
DOCKER_DEB="docker-desktop-amd64.deb"

# ----------------------------------------
# Helper: Check if Docker is installed
# ----------------------------------------
check_docker_installed() {
    if command -v docker >/dev/null 2>&1; then
        echo "✔ Docker is already installed"
        echo "Version: $(docker --version)"
        echo "Status:"
        sudo systemctl status docker --no-pager
        return 0
    else
        return 1
    fi
}

# ----------------------------------------
# Fix/Reinstall: Remove all conflicting keys & installs
# ----------------------------------------
fix_existing_install() {
    echo "⚠ Fixing conflicts + removing old Docker installs..."

    sudo rm -f /etc/apt/sources.list.d/docker.list
    sudo rm -f /etc/apt/sources.list.d/docker-desktop.list
    sudo rm -f /etc/apt/keyrings/docker.gpg
    sudo rm -f /etc/apt/keyrings/docker.asc

    sudo apt remove -y $(dpkg --get-selections \
        | grep -E "docker|containerd|runc" \
        | cut -f1) || true

    sudo apt purge -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras || true

    sudo apt autoremove -y
    sudo apt autoclean -y

    echo "✔ Cleanup completed"
}

# ----------------------------------------
# Install Docker Engine (default method)
# ----------------------------------------
install_docker_default() {
    echo "⚙ Installing Docker Engine (official repo)..."

    sudo apt update
    sudo apt install -y ca-certificates curl gnupg

    sudo install -m 0755 -d /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    source /etc/os-release
    echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu $VERSION_CODENAME stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    sudo systemctl enable docker
    sudo systemctl start docker

    echo "✔ Docker Engine installed successfully"
}

# ----------------------------------------
# Install Docker Desktop (.deb)
# ----------------------------------------
install_docker_desktop() {
    echo "📦 Installing Docker Desktop..."

    mkdir -p ~/downloads

    if [ ! -f ~/downloads/${DOCKER_DEB} ]; then
        echo "⬇ Downloading Docker Desktop..."
        wget -O ~/downloads/${DOCKER_DEB} "${DOCKER_DESKTOP_URL}"
    else
        echo "✔ Docker Desktop installer already present"
    fi

    fix_existing_install

    sudo apt update
    sudo apt install -y ~/downloads/${DOCKER_DEB}

    echo "✔ Docker Desktop installed successfully"
}

# ----------------------------------------
# Install via Convenience Script
# ----------------------------------------
install_convenience_script() {
    echo "⚙ Installing Docker using convenience script..."

    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    rm get-docker.sh

    echo "✔ Docker installed using convenience script"
}

# ----------------------------------------
# Uninstall Docker completely
# ----------------------------------------
uninstall_docker() {
    echo "🧹 Uninstalling Docker (any version)..."

    # Stop services
    sudo systemctl stop docker docker.socket containerd || true
    sudo systemctl disable docker docker.socket containerd || true

    # Remove packages (any type)
    sudo apt remove -y \
        docker.io docker-doc docker-compose docker-compose-v2 \
        docker-ce docker-ce-cli docker-ce-rootless-extras \
        docker-desktop containerd containerd.io buildah podman runc || true

    sudo apt purge -y \
        docker.io docker-doc docker-compose docker-compose-v2 \
        docker-ce docker-ce-cli docker-ce-rootless-extras \
        docker-desktop containerd containerd.io || true

    # Remove APT repos
    sudo rm -f /etc/apt/sources.list.d/docker.list
    sudo rm -f /etc/apt/sources.list.d/docker-desktop.list

    # Remove keys
    sudo rm -f /etc/apt/keyrings/docker.gpg
    sudo rm -f /etc/apt/keyrings/docker.asc

    sudo apt autoremove -y
    sudo apt autoclean -y

    if [[ "$1" == "--purge" ]]; then
        echo "⚠ Purging Docker data from /var/lib/docker and /var/lib/containerd"
        sudo rm -rf /var/lib/docker
        sudo rm -rf /var/lib/containerd
    fi

    echo "✔ Docker uninstalled successfully"
}

# ----------------------------------------
# MAIN LOGIC
# ----------------------------------------
case "$1" in
    "")
        echo "🔍 Checking if Docker is installed..."
        if check_docker_installed; then
            echo "✔ Nothing to do."
            exit 0
        else
            echo "🚀 Docker not found → Installing default Docker Engine..."
            install_docker_default
        fi
        ;;
    uninstall)
        echo "🚨 Uninstall mode selected"
        uninstall_docker "$2"
        exit 0
        ;;
    fix|reinstall)
        fix_existing_install
        install_docker_default
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
        echo "  ./install-docker.sh           # normal install (default)"
        echo "  ./install-docker.sh fix       # fix + reinstall"
        echo "  ./install-docker.sh desktop   # install Docker Desktop"
        echo "  ./install-docker.sh script    # install via convenience script"
        exit 1
        ;;
esac
