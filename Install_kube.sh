#!/bin/bash

set -e

K8S_VERSION="v1.28"
KEYRING_PATH="/etc/apt/keyrings/kubernetes-apt-keyring.gpg"
REPO_PATH="/etc/apt/sources.list.d/kubernetes.list"

echo "Detecting OS..."

# Get ID from os-release
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION_ID=$VERSION_ID
else
    echo "Unsupported OS: /etc/os-release not found."
    exit 1
fi

# Common utilities
install_common_packages() {
    if command -v apt &>/dev/null; then
        sudo apt update
        sudo apt install -y curl apt-transport-https ca-certificates gnupg
    elif command -v yum &>/dev/null; then
        sudo yum install -y curl
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y curl
    else
        echo "No supported package manager found (apt, yum, dnf)."
        exit 1
    fi
}

# Debian/Ubuntu-based setup
setup_debian() {
    echo "Setting up Kubernetes for Debian/Ubuntu..."
    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key | \
        sudo gpg --dearmor -o "$KEYRING_PATH"
    
    echo "deb [signed-by=${KEYRING_PATH}] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" | \
        sudo tee "$REPO_PATH"

    sudo apt update
    sudo apt install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
}

# RHEL/CentOS/Rocky/AlmaLinux-based setup
setup_rhel() {
    echo "Setting up Kubernetes for RHEL-based systems..."
    sudo tee /etc/yum.repos.d/kubernetes.repo >/dev/null <<EOF
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/rpm/
enabled=1
gpgcheck=1
repo_gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/rpm/repodata/repomd.xml.key
EOF

    sudo yum install -y kubelet kubeadm kubectl --disableexcludes=kubernetes || \
    sudo dnf install -y kubelet kubeadm kubectl --disableexcludes=kubernetes

    sudo systemctl enable --now kubelet
}

# Main
install_common_packages

case "$OS" in
    ubuntu|debian)
        setup_debian
        ;;
    rhel|centos|rocky|almalinux|ol)
        setup_rhel
        ;;
    *)
        echo "Unsupported OS: $OS"
        exit 1
        ;;
esac

echo "✅ Kubernetes tools installed: kubelet, kubeadm, kubectl"
