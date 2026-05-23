# Kubernetes Cluster on Ubuntu 24.04 with Vagrant

Automated Kubernetes cluster provisioning using Vagrant and VMware/VirtualBox. Creates a Kubernetes cluster with CRI-O runtime, Calico networking, Metrics Server, and ArgoCD — all configurable via `settings.yaml`.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Choosing a Hypervisor](#choosing-a-hypervisor)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Project Structure](#project-structure)
- [Usage](#usage)
- [Cleanup](#cleanup)
- [Troubleshooting](#troubleshooting)
- [References](#references)

## Features

- **Kubernetes** (version set in `settings.yaml`) initialized with kubeadm
- **CRI-O** container runtime
- **Calico** for pod networking and network policy
- **Metrics Server** for resource usage (`kubectl top`)
- **ArgoCD** installed and exposed via NodePort (HTTP: 30903, HTTPS: 30904)
- **Helm** installed on the control plane
- **Ubuntu 24.04 LTS** base OS
- **Configurable**: node count, CPU, memory, versions via `settings.yaml`
- **Multi-hypervisor**: VMware Desktop and VirtualBox (see [Choosing a Hypervisor](#choosing-a-hypervisor))
- **Robust provisioning**: retry logic for package downloads, DNS stabilization, swap disabled

## Prerequisites

### System Requirements

- Windows 10/11 or Linux
- **Vagrant** 2.3+
- **Git**
- Minimum 8GB RAM (16GB+ recommended for multi-node), 20GB free disk space

## Choosing a Hypervisor

This project supports two hypervisors. Pick one and follow the corresponding setup — the rest of the instructions are the same after that.

| | VMware Workstation Pro | VirtualBox |
|---|---|---|
| **Branch** | `main` (this branch) | `virtualbox` branch |
| **Performance** | Better (especially on Windows) | Good, free |
| **Vagrant plugin** | `vagrant-vmware-desktop` (paid) | Built-in provider |

### Option A — VMware Workstation Pro

1. Install [VMware Workstation Pro](https://www.vmware.com/products/workstation-pro.html) and [Vagrant](https://www.vagrantup.com/downloads)
2. Install the required Vagrant plugins:
```powershell
vagrant plugin install vagrant-vmware-desktop
vagrant plugin install vagrant-hostmanager
```
3. Use this branch (`main`) — VMware is the default provider, no extra env var needed.

### Option B — VirtualBox

1. Install [VirtualBox](https://www.virtualbox.org/wiki/Downloads) and [Vagrant](https://www.vagrantup.com/downloads)
2. Switch to the VirtualBox branch and install the plugin:
```powershell
git checkout virtualbox
vagrant plugin install vagrant-hostmanager
```
3. Set VirtualBox as the provider before running `vagrant up`:
```powershell
$env:VAGRANT_DEFAULT_PROVIDER = "virtualbox"
```

---

## Quick Start

### 1. Clone Repository

```powershell
git clone <repository-url>
cd k8s_vagrant_win11
```

### 2. Select Hypervisor

Follow [Option A (VMware)](#option-a--vmware-workstation-pro) or [Option B (VirtualBox)](#option-b--virtualbox) above before continuing.

### 3. Configure

Edit `settings.yaml` to set node count, resources, and software versions:

```yaml
nodes:
  workers:
    count: 2
  control:
    cpu: 2
    memory: 6144
software:
  kubernetes: v1.34
  crio: v1.35
  calico: 3.28.2
```

### 4. Launch Cluster

```powershell
# VMware (Option A — default, no env var needed)
vagrant up

# VirtualBox (Option B — set provider first)
$env:VAGRANT_DEFAULT_PROVIDER = "virtualbox"
vagrant up
```

### 5. Verify

```powershell
vagrant status
vagrant ssh control-plane
kubectl get nodes
```

## Configuration

### settings.yaml

| Parameter | Default | Description |
|-----------|---------|-------------|
| `nodes.workers.count` | `2` | Number of worker nodes |
| `nodes.control.cpu` | `2` | Control plane vCPUs |
| `nodes.control.memory` | `6144` | Control plane RAM (MB) |
| `nodes.workers.cpu` | `2` | Worker node vCPUs |
| `nodes.workers.memory` | `6144` | Worker node RAM (MB) |
| `nodes.control.ip` | `192.168.100.10` | Control plane IP |
| `nodes.workers.ip_start` | `192.168.100.20` | First worker IP (increments per node) |
| `network.pod_cidr` | `10.244.0.0/16` | Pod network CIDR |
| `network.service_cidr` | `10.96.0.0/12` | Service network CIDR |
| `network.dns_servers` | `1.1.1.1, 9.9.9.9` | DNS servers for VMs |
| `software.kubernetes` | `v1.34` | Kubernetes version |
| `software.crio` | `v1.35` | CRI-O runtime version |
| `software.calico` | `3.28.2` | Calico version |
| `software.box` | `bento/ubuntu-24.04` | Vagrant base box |
| `shared_folders` | `[]` | Host↔VM folder mappings |

## Project Structure

```
k8s_vagrant_win11/
├── Vagrantfile           # Vagrant configuration (VMware; see virtualbox branch for VirtualBox)
├── settings.yaml         # Cluster configuration
├── aliases.sh            # Useful kubectl bash aliases
├── README.md
├── .gitignore
├── LICENSE
├── configs/              # Generated at provision time (do NOT commit)
│   ├── config            # Kubeconfig for cluster access
│   └── join.sh           # Worker node join command
└── scripts/
    ├── common.sh         # CRI-O, Kubernetes packages, kernel config (all nodes)
    ├── control.sh        # kubeadm init, Calico, Helm, Metrics Server, ArgoCD
    └── node.sh           # Worker join and kubeconfig setup
```

## Usage

### Access the Cluster

```powershell
# SSH into nodes
vagrant ssh control-plane
vagrant ssh node01

# Use kubeconfig from host
$env:KUBECONFIG = "$(Get-Location)\configs\config"
kubectl get nodes
```

### Kubectl Aliases

Source `aliases.sh` inside the VM for handy shortcuts:

```bash
source /vagrant/aliases.sh

k get nodes          # kubectl
kaa                  # kubectl get all -A
kn kube-system       # set current namespace
kd <pod>             # force delete pod
```

### ArgoCD

ArgoCD is installed in the `argocd` namespace and exposed as NodePort:

```bash
# Get initial admin password
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d

# Access UI
# HTTP:  http://192.168.100.10:30903
# HTTPS: https://192.168.100.10:30904

# Login via CLI
argocd login 192.168.100.10:30904 --insecure
```

### Port Forwarding Options

**kubectl port-forward (recommended for ad-hoc access):**
```bash
kubectl port-forward svc/my-service 8080:80
```

**NodePort service:**
```bash
kubectl expose deployment nginx --type=NodePort --port=80
kubectl get svc nginx  # note the assigned port, e.g. 30123
# Access: http://192.168.100.10:30123
```

**Persistent forwarding via Vagrantfile:**
```ruby
control.vm.network "forwarded_port", guest: 8080, host: 8080
```
Then apply: `vagrant reload`

### Common kubectl Commands

```bash
# Cluster status
kubectl get nodes
kubectl get pods -A
kubectl cluster-info

# Deploy and expose
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=NodePort

# Debugging
kubectl describe node <node-name>
kubectl logs -f <pod-name>
kubectl get events -A --sort-by='.lastTimestamp'
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- bash
```

## Cleanup

```powershell
# Destroy all VMs and clean up
vagrant destroy -f
Remove-Item -Path configs\* -Force
Remove-Item -Path .vagrant -Recurse -Force

# Non-destructive operations
vagrant halt       # Stop VMs
vagrant suspend    # Suspend to disk
vagrant resume     # Resume from suspend
vagrant reload     # Restart and re-apply Vagrantfile config
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| **Package download fails** | Retry logic is built in. Check connectivity: `ping 8.8.8.8`. Rebuild: `vagrant destroy -f && vagrant up` |
| **Insufficient resources** | Check RAM: `Get-ComputerInfo \| Select TotalPhysicalMemory`. Lower `memory` or `count` in `settings.yaml` |
| **Kubeconfig not working** | Verify control plane is up: `vagrant status`. Re-provision: `vagrant up --provision` |
| **Calico pods crashing** | Check logs: `kubectl logs -n kube-system -l k8s-app=calico-node`. Verify `pod_cidr` is not in use |
| **Worker node join fails** | Confirm control plane is ready: `kubectl get nodes`. Check token: `kubeadm token list` |
| **ArgoCD unreachable** | Check pods: `kubectl get pods -n argocd`. Verify NodePort: `kubectl get svc -n argocd` |

**Debug provisioning:**
```powershell
vagrant up --debug 2>&1 | Tee-Object -FilePath provision.log
vagrant ssh control-plane -- sudo journalctl -xe
```

## References

- [Vagrant Docs](https://www.vagrantup.com/docs)
- [Kubernetes Docs](https://kubernetes.io/docs/)
- [kubeadm Guide](https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/)
- [CRI-O Docs](https://cri-o.io/)
- [Calico Docs](https://docs.tigera.io/calico/latest/)
- [ArgoCD Docs](https://argo-cd.readthedocs.io/)
- [Helm Docs](https://helm.sh/docs/)

## Notes

- **Development only**: Not hardened for production use
- **Never commit** the `configs/` directory — it contains cluster credentials
- Allow VM↔Host traffic through your host firewall for NodePort and ArgoCD access
