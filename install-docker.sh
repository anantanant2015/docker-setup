#!/usr/bin/env bash
set -e

DOCKER_DESKTOP_URL="https://desktop.docker.com/linux/main/amd64/docker-desktop-amd64.deb"
DOCKER_DEB="docker-desktop-amd64.deb"

# Detect CI environment (GitHub Actions or others)
if [ "${CI}" = "true" ] || [ "${GITHUB_ACTIONS}" = "true" ]; then
    IN_CI=1
else
    IN_CI=0
fi

# ----------------------------------------
# Helper: Check if Docker is installed
# ----------------------------------------
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

# ----------------------------------------
# Fix/Reinstall: Remove conflicting installs
# ----------------------------------------
fix_existing_install() {
    if [ "$IN_CI" -eq 1 ]; then
        echo "⏭️  fix mode skipped (CI mode)"
        return 0
    fi

    echo "⚠ Fixing conflicts + removing old Docker installs..."

    sudo rm -f /etc/apt/sources.list.d/docker.list
    sudo rm -f /etc/apt/sources.list.d/docker-desktop.list
    sudo rm -f /etc/apt/keyrings/docker.gpg
    sudo rm -f /etc/apt/keyrings/docker.asc

    # SC2046 fix (quote expansion)
    mapfile -t pkgs < <(dpkg --get-selections | awk '/docker|containerd|runc/ {print $1}')
    if [ "${#pkgs[@]}" -gt 0 ]; then
        sudo apt remove -y "${pkgs[@]}" || true
    fi

    sudo apt purge -y docker-ce docker-ce-cli containerd.io \
        docker-buildx-plugin docker-compose-plugin docker-ce-rootless-extras || true

    sudo apt autoremove -y
    sudo apt autoclean -y

    echo "✔ Cleanup completed"
}

# ----------------------------------------
# Install Docker Engine
# ----------------------------------------
install_docker_default() {
    if [ "$IN_CI" -eq 1 ]; then
        echo "⏭️  install_docker_default skipped (CI mode)"
        return 0
    fi

    echo "⚙ Installing Docker Engine (official repo)..."

    sudo apt update
    sudo apt install -y ca-certificates curl gnupg

    sudo install -m 0755 -d /etc/apt/keyrings

    curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
        | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    # shellcheck source=/dev/null
    if [ -f /etc/os-release ]; then
        source /etc/os-release
    else
        VERSION_CODENAME="focal"
    fi

    echo \
"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/ubuntu ${VERSION_CODENAME} stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt update
    sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    sudo systemctl enable docker || true
    sudo systemctl start docker || true

    echo "✔ Docker Engine installed successfully"
}

# ----------------------------------------
# Install Docker Desktop
# ----------------------------------------
install_docker_desktop() {
    if [ "$IN_CI" -eq 1 ]; then
        echo "⏭️  Docker Desktop install skipped (CI mode)"
        return 0
    fi

    echo "📦 Installing Docker Desktop..."
    mkdir -p ~/downloads

    if [ ! -f ~/downloads/${DOCKER_DEB} ]; then
        echo "⬇ Downloading Docker Desktop..."
        wget -O ~/downloads/${DOCKER_DEB} "${DOCKER_DESKTOP_URL}"
    else
        echo "✔ Installer already present"
    fi

    fix_existing_install

    sudo apt update
    sudo apt install -y ~/downloads/${DOCKER_DEB}
}

# ----------------------------------------
# Install via convenience script
# ----------------------------------------
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

# ----------------------------------------
# Uninstall Docker entirely
# ----------------------------------------
uninstall_docker() {
    if [ "$IN_CI" -eq 1 ]; then
        echo "⏭️  Uninstall skipped (CI mode)"
        return 0
    fi

    echo "🧹 Uninstalling Docker..."

    sudo systemctl stop docker docker.socket containerd || true
    sudo systemctl disable docker docker.socket containerd || true

    sudo apt remove -y \
        docker.io docker-doc docker-compose docker-compose-v2 \
        docker-ce docker-ce-cli docker-ce-rootless-extras \
        docker-desktop containerd containerd.io buildah podman runc || true

    sudo apt purge -y \
        docker.io docker-doc docker-compose docker-compose-v2 \
        docker-ce docker-ce-cli docker-ce-rootless-extras \
        docker-desktop containerd containerd.io || true

    sudo rm -f /etc/apt/sources.list.d/docker.list
    sudo rm -f /etc/apt/sources.list.d/docker-desktop.list

    sudo rm -f /etc/apt/keyrings/docker.gpg
    sudo rm -f /etc/apt/keyrings/docker.asc

    sudo apt autoremove -y
    sudo apt autoclean -y

    if [[ "$1" == "--purge" ]]; then
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
        fi
        echo "🚀 Installing default Docker Engine..."
        install_docker_default
        ;;
    uninstall)
        echo "🚨 Uninstall mode selected"
        uninstall_docker "$2"
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
        echo "  ./install-docker.sh"
        echo "  ./install-docker.sh fix"
        echo "  ./install-docker.sh desktop"
        echo "  ./install-docker.sh script"
        exit 2
        ;;
esac
