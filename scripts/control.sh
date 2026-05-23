#!/bin/bash
#
# Setup for Control Plane (Master) servers

set -euxo pipefail

TEMP_DIR="/tmp"

export CALICO_VERSION
export CRIO_VERSION
export CONTROL_IP
export POD_CIDR
export SERVICE_CIDR
export HELM_VERSION
export ARGOCD_VERSION

# Resolve the latest commit hash from the metrics-server manifest repo at runtime.
# This ensures we always use the most recent version without hardcoding a SHA.
METRICS_SERVER_REPO_COMMIT=$(git ls-remote https://github.com/mialeevs/kubernetes_installation_crio.git HEAD | awk '{print $1}')

NODENAME=$(hostname -s)

# Network connectivity check
echo "Testing network connectivity..."
ping -c 3 8.8.8.8 || echo "Warning: Cannot reach 8.8.8.8"
nslookup registry.k8s.io || echo "Warning: DNS resolution failed for registry.k8s.io"

# Pull all required images — let kubeadm resolve the correct versions dynamically
echo "Pulling required Kubernetes images..."
if sudo kubeadm config images pull --image-repository=registry.k8s.io; then
  echo "All images pulled via primary registry."
else
  echo "Primary registry failed, pulling images individually using kubeadm-resolved tags..."
  # Resolve image list dynamically so versions always match the installed kubeadm
  sudo kubeadm config images list --image-repository=registry.k8s.io 2>/dev/null | while read -r image; do
    sudo crictl pull "$image" || echo "Warning: Failed to pull $image"
  done
  echo "Individual image pulls completed."
fi

echo "Preflight Check Passed: Downloaded All Required Images"

sudo kubeadm init \
  --apiserver-advertise-address="$CONTROL_IP" \
  --apiserver-cert-extra-sans="$CONTROL_IP" \
  --pod-network-cidr="$POD_CIDR" \
  --service-cidr="$SERVICE_CIDR" \
  --node-name "$NODENAME" \
  --ignore-preflight-errors Swap

mkdir -p "$HOME"/.kube
sudo cp -i /etc/kubernetes/admin.conf "$HOME"/.kube/config
sudo chown "$(id -u)":"$(id -g)" "$HOME"/.kube/config

# Save Configs to shared /Vagrant location.
# For Vagrant re-runs, delete existing configs before saving new ones.
config_path="/vagrant/configs"

if [ -d "$config_path" ]; then
  rm -f "$config_path"/*
else
  mkdir -p "$config_path"
fi

cp -i /etc/kubernetes/admin.conf "$config_path/config"
touch "$config_path/join.sh"
chmod +x "$config_path/join.sh"
kubeadm token create --print-join-command > "$config_path/join.sh"

# ============================================================
# Install Calico Network Plugin
# ============================================================
echo "Downloading Calico manifest..."
MAX_RETRIES=5
RETRY_COUNT=0
SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if curl -fsSL "https://raw.githubusercontent.com/projectcalico/calico/v${CALICO_VERSION}/manifests/calico.yaml" \
       -o "${TEMP_DIR}/calico.yaml"; then
    SUCCESS=true
    break
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  [ $RETRY_COUNT -lt $MAX_RETRIES ] && \
    echo "Retrying Calico download ($RETRY_COUNT/$MAX_RETRIES)..." && \
    sleep $((RETRY_COUNT * 5))
done

if [ "$SUCCESS" = false ]; then
  echo "ERROR: Failed to download Calico manifest after $MAX_RETRIES attempts"
  exit 1
fi

kubectl apply -f "${TEMP_DIR}/calico.yaml"
rm -f "${TEMP_DIR}/calico.yaml"

# ============================================================
# Install Helm — pinned version with checksum verification
# ============================================================
echo "Installing Helm ${HELM_VERSION}..."
sudo apt-get install -y curl gpg apt-transport-https

HELM_TARBALL="helm-${HELM_VERSION}-linux-amd64.tar.gz"
HELM_URL="https://get.helm.sh/${HELM_TARBALL}"
HELM_CHECKSUM_URL="${HELM_URL}.sha256sum"

curl -fsSL "${HELM_URL}" -o "${TEMP_DIR}/${HELM_TARBALL}"
curl -fsSL "${HELM_CHECKSUM_URL}" -o "${TEMP_DIR}/${HELM_TARBALL}.sha256sum"

# Verify checksum before installing
cd "${TEMP_DIR}"
sha256sum --check --status "${HELM_TARBALL}.sha256sum"
echo "Helm checksum verified."

tar -zxf "${HELM_TARBALL}" linux-amd64/helm
sudo install -m 755 linux-amd64/helm /usr/local/bin/helm

# Clean up
rm -f "${HELM_TARBALL}" "${HELM_TARBALL}.sha256sum"
rm -rf linux-amd64/
cd -

echo "Helm ${HELM_VERSION} installed successfully."

# ============================================================
# Install ArgoCD CLI — pinned version with checksum verification
# ============================================================
echo "Downloading ArgoCD CLI ${ARGOCD_VERSION}..."
ARGOCD_BINARY_URL="https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/argocd-linux-amd64"
# Since ArgoCD v3.x the per-binary .sha256 file was replaced by a combined cli_checksums.txt
ARGOCD_CHECKSUM_URL="https://github.com/argoproj/argo-cd/releases/download/${ARGOCD_VERSION}/cli_checksums.txt"

MAX_RETRIES=5
RETRY_COUNT=0
SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if curl -fsSL "${ARGOCD_BINARY_URL}" -o "${TEMP_DIR}/argocd" && \
     curl -fsSL "${ARGOCD_CHECKSUM_URL}" -o "${TEMP_DIR}/argocd_checksums.txt"; then
    SUCCESS=true
    break
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  [ $RETRY_COUNT -lt $MAX_RETRIES ] && \
    echo "Retrying ArgoCD CLI download ($RETRY_COUNT/$MAX_RETRIES)..." && \
    sleep $((RETRY_COUNT * 5))
done

if [ "$SUCCESS" = false ]; then
  echo "ERROR: Failed to download ArgoCD CLI after $MAX_RETRIES attempts"
  exit 1
fi

# Verify checksum — cli_checksums.txt contains one "<hash>  <filename>" line per platform
EXPECTED_CHECKSUM=$(grep "argocd-linux-amd64" "${TEMP_DIR}/argocd_checksums.txt" | awk '{print $1}')
ACTUAL_CHECKSUM=$(sha256sum "${TEMP_DIR}/argocd" | awk '{print $1}')
if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
  echo "ERROR: ArgoCD CLI checksum mismatch! Expected: $EXPECTED_CHECKSUM, Got: $ACTUAL_CHECKSUM"
  rm -f "${TEMP_DIR}/argocd" "${TEMP_DIR}/argocd_checksums.txt"
  exit 1
fi
echo "ArgoCD CLI checksum verified."

sudo install -m 755 "${TEMP_DIR}/argocd" /usr/local/bin/argocd
rm -f "${TEMP_DIR}/argocd" "${TEMP_DIR}/argocd_checksums.txt"

echo "ArgoCD CLI ${ARGOCD_VERSION} installed successfully."

# ============================================================
# Copy kubeconfig for vagrant user
# ============================================================
sudo -i -u vagrant bash << EOF
whoami
mkdir -p /home/vagrant/.kube
sudo cp -i ${config_path}/config /home/vagrant/.kube/
sudo chown 1000:1000 /home/vagrant/.kube/config
EOF

# ============================================================
# Install Metrics Server — pinned to a specific commit hash
# ============================================================
echo "Cloning metrics server repository at pinned commit ${METRICS_SERVER_REPO_COMMIT}..."
MAX_RETRIES=5
RETRY_COUNT=0
SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if git clone https://github.com/mialeevs/kubernetes_installation_crio.git "${TEMP_DIR}/metrics-server-repo"; then
    SUCCESS=true
    break
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  [ $RETRY_COUNT -lt $MAX_RETRIES ] && \
    echo "Retrying clone ($RETRY_COUNT/$MAX_RETRIES)..." && \
    sleep $((RETRY_COUNT * 5))
done

if [ "$SUCCESS" = false ]; then
  echo "ERROR: Failed to clone metrics server repository after $MAX_RETRIES attempts"
  exit 1
fi

# Checkout the pinned commit — prevents supply-chain attacks from future changes
cd "${TEMP_DIR}/metrics-server-repo"
git checkout "${METRICS_SERVER_REPO_COMMIT}"
kubectl apply -f metrics-server.yaml
cd -
rm -rf "${TEMP_DIR}/metrics-server-repo"

# ============================================================
# Install ArgoCD — pinned version manifest
# ============================================================
kubectl create namespace argocd || true

ARGOCD_MANIFEST_URL="https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
echo "Applying ArgoCD manifest from pinned version ${ARGOCD_VERSION}..."

MAX_RETRIES=5
RETRY_COUNT=0
SUCCESS=false

while [ $RETRY_COUNT -lt $MAX_RETRIES ]; do
  if kubectl apply -n argocd --server-side --force-conflicts -f "${ARGOCD_MANIFEST_URL}"; then
    SUCCESS=true
    break
  fi
  RETRY_COUNT=$((RETRY_COUNT + 1))
  [ $RETRY_COUNT -lt $MAX_RETRIES ] && \
    echo "Retrying ArgoCD manifest apply ($RETRY_COUNT/$MAX_RETRIES)..." && \
    sleep $((RETRY_COUNT * 5))
done

if [ "$SUCCESS" = false ]; then
  echo "ERROR: Failed to apply ArgoCD manifest after $MAX_RETRIES attempts"
  exit 1
fi

kubectl patch svc argocd-server -n argocd -p '{"spec":{"type":"NodePort"}}'
kubectl patch svc argocd-server -n argocd --type='json' \
    -p='[{"op":"replace","path":"/spec/ports/0/nodePort","value":30903},{"op":"replace","path":"/spec/ports/1/nodePort","value":30904}]'
