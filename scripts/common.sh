#!/bin/bash
#
# Common setup for all servers (Control Plane and Nodes)

set -euxo pipefail

# Wait for DNS to be ready
echo "Waiting for DNS resolution to be available..."
for i in {1..30}; do
  if nslookup 8.8.8.8 > /dev/null 2>&1; then
    echo "DNS is ready"
    break
  fi
  if [ $i -eq 30 ]; then
    echo "Warning: DNS not responding after 30 attempts, continuing anyway..."
  fi
  sleep 1
done

# Allow system to stabilize after boot
echo "Waiting for system to stabilize..."
sleep 15

# Variable Declaration
export DNS_SERVERS
export KUBERNETES_VERSION
export CRIO_VERSION
export ENVIRONMENT
export OS

# DNS Setting
if [ ! -d /etc/systemd/resolved.conf.d ]; then
	sudo mkdir /etc/systemd/resolved.conf.d/
fi
cat <<EOF | sudo tee /etc/systemd/resolved.conf.d/dns_servers.conf
[Resolve]
DNS=${DNS_SERVERS}
EOF

sudo systemctl restart systemd-resolved

# disable swap
sudo swapoff -a

# keeps the swap off during reboot
(crontab -l 2>/dev/null; echo "@reboot /sbin/swapoff -a") | crontab - || true
sudo apt-get update -y
# Install CRI-O Runtime

VERSION="$(echo ${KUBERNETES_VERSION} | grep -oE '[0-9]+\.[0-9]+')"

# Create the .conf file to load the modules at bootup
cat <<EOF | sudo tee /etc/modules-load.d/crio.conf
overlay
br_netfilter
EOF

sudo modprobe overlay
sudo modprobe br_netfilter

# Set up required sysctl params, these persist across reboots.
cat <<EOF | sudo tee /etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.ipv4.ip_forward                 = 1
net.bridge.bridge-nf-call-ip6tables = 1
EOF

sudo sysctl --system

sudo mkdir -p /etc/apt/keyrings

# Download CRI-O GPG key with retry logic
echo "Downloading CRI-O GPG key..."
MAX_RETRIES=5
RETRY_COUNT=0
SUCCESS=false
CRIO_KEY_TMP="/tmp/crio-release.key"

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  # Download to temporary file first
  if curl -fsSL "https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/Release.key" -o $CRIO_KEY_TMP; then
    # Check if file is not empty and contains valid GPG data
    if [ -s $CRIO_KEY_TMP ] && grep -q "BEGIN PGP" $CRIO_KEY_TMP; then
      # Process the key
      if sudo gpg --dearmor -o /etc/apt/keyrings/cri-o-apt-keyring.gpg < $CRIO_KEY_TMP 2>/dev/null; then
        SUCCESS=true
        break
      fi
    fi
  fi
  
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
    echo "Failed to download/process CRI-O GPG key (attempt $RETRY_COUNT/$MAX_RETRIES). Retrying in $((RETRY_COUNT * 5)) seconds..."
    sleep $((RETRY_COUNT * 5))
  fi
done

if [ "$SUCCESS" = false ]; then
  echo "ERROR: Failed to download CRI-O GPG key after $MAX_RETRIES attempts"
  exit 1
fi

rm -f $CRIO_KEY_TMP

echo "deb [signed-by=/etc/apt/keyrings/cri-o-apt-keyring.gpg] https://download.opensuse.org/repositories/isv:/cri-o:/stable:/$CRIO_VERSION/deb/ /" \
  | sudo tee /etc/apt/sources.list.d/cri-o.list

sudo apt-get update -y
sudo apt-get install cri-o -y

cat >> /etc/default/crio << EOF
${ENVIRONMENT}
EOF
sudo systemctl daemon-reload
sudo systemctl enable crio --now

echo "CRI runtime installed successfully"

sudo apt-get update -y

sudo apt-get install -y apt-transport-https ca-certificates curl gpg

# Download Kubernetes GPG key with retry logic
echo "Downloading Kubernetes GPG key..."
MAX_RETRIES=5
RETRY_COUNT=0
SUCCESS=false
KUBE_KEY_TMP="/tmp/kubernetes-release.key"

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  # Download to temporary file first
  if sudo curl -fsSL https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/Release.key -o $KUBE_KEY_TMP; then
    # Check if file is not empty and contains valid GPG data
    if [ -s $KUBE_KEY_TMP ] && sudo gpg --with-colons $KUBE_KEY_TMP > /dev/null 2>&1 || grep -q "BEGIN PGP" $KUBE_KEY_TMP; then
      # Process the key
      if sudo gpg --dearmor -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg < $KUBE_KEY_TMP 2>/dev/null; then
        SUCCESS=true
        break
      fi
    fi
  fi
  
  RETRY_COUNT=$((RETRY_COUNT + 1))
  if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
    echo "Failed to download/process Kubernetes GPG key (attempt $RETRY_COUNT/$MAX_RETRIES). Retrying in $((RETRY_COUNT * 5)) seconds..."
    sleep $((RETRY_COUNT * 5))
  fi
done

if [ "$SUCCESS" = false ]; then
  echo "ERROR: Failed to download Kubernetes GPG key after $MAX_RETRIES attempts"
  exit 1
fi

sudo rm -f $KUBE_KEY_TMP
sudo chmod 644 /etc/apt/keyrings/kubernetes-apt-keyring.gpg # allow unprivileged APT programs to read this keyring

sudo echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/$KUBERNETES_VERSION/deb/ /" | sudo tee /etc/apt/sources.list.d/kubernetes.list

# Update apt-get with retry logic for Kubernetes repository
echo "Updating apt-get with Kubernetes repository..."
MAX_RETRIES=5
RETRY_COUNT=0
SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if sudo apt-get update -y; then
    SUCCESS=true
    break
  else
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
      echo "Failed to update apt-get (attempt $RETRY_COUNT/$MAX_RETRIES). Retrying in $((RETRY_COUNT * 10)) seconds..."
      sleep $((RETRY_COUNT * 10))
    fi
  fi
done

if [ "$SUCCESS" = false ]; then
  echo "WARNING: Failed to update apt-get after $MAX_RETRIES attempts, but continuing..."
fi

# Install Kubernetes packages with retry logic
echo "Installing Kubernetes packages..."
RETRY_COUNT=0
SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if sudo apt-get install -y kubelet kubeadm kubectl; then
    SUCCESS=true
    break
  else
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
      echo "Failed to install Kubernetes packages (attempt $RETRY_COUNT/$MAX_RETRIES). Retrying in $((RETRY_COUNT * 10)) seconds..."
      sleep $((RETRY_COUNT * 10))
    fi
  fi
done

if [ "$SUCCESS" = false ]; then
  echo "ERROR: Failed to install Kubernetes packages after $MAX_RETRIES attempts"
  exit 1
fi

# Install jq with retry logic
echo "Installing jq..."
RETRY_COUNT=0
SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if sudo apt-get install -y jq; then
    SUCCESS=true
    break
  else
    RETRY_COUNT=$((RETRY_COUNT + 1))
    if [ $RETRY_COUNT -lt $MAX_RETRIES ]; then
      echo "Failed to install jq (attempt $RETRY_COUNT/$MAX_RETRIES). Retrying in $((RETRY_COUNT * 10)) seconds..."
      sleep $((RETRY_COUNT * 10))
    fi
  fi
done

if [ "$SUCCESS" = false ]; then
  echo "WARNING: Failed to install jq, but continuing..."
fi

local_ip="$(ip --json a s | jq -r '.[] | if .ifname == "eth1" then .addr_info[] | if .family == "inet" then .local else empty end else empty end')"
cat > /etc/default/kubelet << EOF
KUBELET_EXTRA_ARGS=--node-ip=$local_ip
${ENVIRONMENT}
EOF
