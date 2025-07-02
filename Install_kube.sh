#!/bin/bash

set -e

K8S_VERSION="v1.28"
KEYRING_PATH="/etc/apt/keyrings/kubernetes-apt-keyring.gpg"
REPO_PATH="/etc/apt/sources.list.d/kubernetes.list"

echo "[+] Detecting OS..."

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION_ID=$VERSION_ID
else
    echo "[x] Unsupported OS: /etc/os-release not found."
    exit 1
fi

install_common_packages() {
    if command -v apt &>/dev/null; then
        sudo apt update
        sudo apt install -y curl apt-transport-https ca-certificates gnupg
    elif command -v yum &>/dev/null; then
        sudo yum install -y curl
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y curl
    else
        echo "[x] No supported package manager found (apt, yum, dnf)."
        exit 1
    fi
}

setup_debian() {
    echo "[+] Setting up Kubernetes repo for Debian/Ubuntu..."

    sudo mkdir -p /etc/apt/keyrings
    curl -fsSL https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/Release.key | \
        sudo gpg --dearmor -o "$KEYRING_PATH"

    echo "deb [signed-by=${KEYRING_PATH}] https://pkgs.k8s.io/core:/stable:/${K8S_VERSION}/deb/ /" | \
        sudo tee "$REPO_PATH"

    sudo apt update
    sudo apt install -y kubelet kubeadm kubectl
    sudo apt-mark hold kubelet kubeadm kubectl
}

setup_rhel() {
    echo "[+] Setting up Kubernetes repo for RHEL/CentOS/Rocky/Alma..."

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

enable_kernel_settings() {
    echo "[+] Configuring kernel modules and sysctl for Kubernetes networking..."

    # Load module immediately
    sudo modprobe br_netfilter

    # Ensure it's loaded on boot
    echo "br_netfilter" | sudo tee /etc/modules-load.d/k8s.conf

    # Add sysctl params
    cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

    # Apply sysctl settings
    sudo sysctl --system
}

### Run full setup

install_common_packages
enable_kernel_settings

case "$OS" in
    ubuntu|debian)
        setup_debian
        ;;
    rhel|centos|rocky|almalinux|ol)
        setup_rhel
        ;;
    *)
        echo "[x] Unsupported OS: $OS"
        exit 1
        ;;
esac

echo "✅ Kubernetes tools installed: kubelet, kubeadm, kubectl"
echo "✅ Kernel and sysctl settings applied"
