# Kubernetes Cluster on Ubuntu 24.04 with Vagrant

Automated Kubernetes cluster provisioning using Vagrant and VirtualBox. This project creates a production-ready Kubernetes cluster (v1.34) with CRI-O runtime, Calico networking, and configurable node count.

## Table of Contents

- [Features](#features)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [Configuration](#configuration)
- [Project Structure](#project-structure)
- [Cluster Information](#cluster-information)
- [Usage](#usage)
- [Cleanup](#cleanup)
- [Troubleshooting](#troubleshooting)
- [References](#references)

## Features

- **Kubernetes v1.34** with kubeadm initialization
- **CRI-O v1.34** container runtime for improved performance
- **Calico v3.28.2** for network policy and pod networking
- **Ubuntu 24.04 LTS** as base operating system
- **Configurable cluster**: adjust node count, CPU, memory via `settings.yaml`
- **Multi-hypervisor support**: VirtualBox
- **Automated provisioning**: DNS, networking, swap management
- **Robust error handling**: Retry logic for transient network issues
- **Kubeconfig generation**: Auto-configured for immediate cluster access

## Prerequisites

### System Requirements

- Windows 10/11 or Linux
- **VirtualBox** 7.0+
- **Vagrant** 2.3+, **Git**
- Minimum 8GB RAM (16GB+ for multi-node cluster), 20GB disk space

### Installation

```powershell
# 1. Install VirtualBox and Vagrant
# 2. Install Vagrant plugins
vagrant plugin install vagrant-hostmanager
```

## Quick Start

### 1. Clone Repository

```powershell
git clone <repository-url>
cd k8s_vagrant_win11
```

### 2. Configure (Edit settings.yaml)

```yaml
nodes:
  workers:
    count: 2
  control:
    cpu: 2
    memory: 6144
software:
  kubernetes: v1.34
```

### 3. Launch Cluster

```powershell
vagrant up
```

### 4. Verify

```powershell
vagrant status
vagrant ssh control-plane
kubectl get nodes
```

## Configuration

### settings.yaml

Key configuration parameters:

| Parameter | Default | Description |
|-----------|---------|-------------|
| `nodes.workers.count` | 2 | Number of worker nodes |
| `nodes.control.cpu` | 2 | Control plane vCPUs |
| `nodes.control.memory` | 6144 | Control plane RAM (MB) |
| `pod_cidr` | 10.244.0.0/16 | Pod network |
| `service_cidr` | 10.96.0.0/12 | Service network |
| `kubernetes` | v1.34 | Kubernetes version |
| `crio` | v1.34 | CRI-O runtime version |
| `calico` | 3.28.2 | Calico network plugin version |

**Network Details:**
- Control Plane: 192.168.100.10
- Worker Nodes: 192.168.100.20+

## Project Structure

```
k8s_vagrant_win11/
├── Vagrantfile           # Main Vagrant configuration
├── settings.yaml         # Cluster configuration
├── README.md            # This file
├── .gitignore           # Git ignore rules
├── LICENSE              # Project license
├── aliases.sh           # Useful bash aliases
├── configs/             # Generated kubeconfig files (do NOT commit)
│   ├── config           # Kubeconfig for cluster access
│   └── join.sh          # Worker node join script
└── scripts/
    ├── common.sh        # Common setup (DNS, CRI-O, k8s packages)
    ├── control.sh       # Control plane initialization
    └── node.sh          # Worker node configuration
```

## Cluster Information

**What Gets Installed:**
- CRI-O container runtime
- Kubernetes tools (kubelet, kubeadm, kubectl)
- Calico network plugin
- System configuration: swap disabled, IP forwarding enabled, required kernel modules

**Generated Files:**
- `configs/config` - Kubeconfig for cluster access
- `configs/join.sh` - Worker node join command (auto-executed)

## Usage

### Access the Cluster

```powershell
# SSH into VMs
vagrant ssh control-plane
vagrant ssh node01

# From host using kubeconfig
$env:KUBECONFIG="$(Get-Location)\configs\config"
kubectl get nodes
```

### Port Forwarding to Host

**Method 1: kubectl port-forward (Recommended)**

```bash
# Forward service to localhost
kubectl port-forward svc/nginx 8080:80

# Forward dashboard
kubectl port-forward -n kubernetes-dashboard svc/kubernetes-dashboard 8443:443
```

**Method 2: SSH Tunnel**

```bash
# Create SSH tunnel through Vagrant
vagrant ssh control-plane -- -N -L 8080:localhost:8080
```

**Method 3: NodePort Service**

```bash
# Expose service as NodePort
kubectl expose deployment nginx --type=NodePort --port=80
kubectl get svc nginx  # Find assigned port (e.g., 30123)
# Access: http://192.168.100.10:30123
```

**Method 4: Persistent Port Forwarding (Edit Vagrantfile)**

```ruby
control.vm.network "forwarded_port", guest: 8080, host: 8080
control.vm.network "forwarded_port", guest: 8443, host: 8443
```

Then restart: `vagrant reload`

### Essential Commands

```bash
# Cluster and node status
kubectl get nodes
kubectl cluster-info
kubectl describe node <node-name>

# View pods and workloads
kubectl get pods -A
kubectl get deployments -A
kubectl get events -A --sort-by='.lastTimestamp'

# Deploy test app
kubectl create deployment nginx --image=nginx
kubectl expose deployment nginx --port=80 --type=NodePort

# Logs and debugging
kubectl logs -f <pod-name>
kubectl run -it --rm debug --image=nicolaka/netshoot --restart=Never -- bash
```

## Cleanup

```powershell
# Full cleanup
vagrant destroy -f
Remove-Item -Path configs/* -Force
Remove-Item -Path .vagrant -Recurse -Force

# Partial operations
vagrant halt      # Stop without destroying
vagrant suspend   # Suspend to disk
vagrant resume    # Resume from suspend
vagrant reload    # Restart with config reload
```

## Troubleshooting

| Issue | Solution |
|-------|----------|
| **Package download fails** | Scripts include retry logic. Check internet: `ping 8.8.8.8`. Rebuild: `vagrant destroy -f && vagrant up` |
| **Insufficient resources** | Check RAM: `Get-ComputerInfo \| Select TotalPhysicalMemory`. Reduce node count/memory in `settings.yaml` |
| **Kubeconfig access denied** | Verify control plane running: `vagrant status`. Regenerate: `vagrant up --provision` |
| **Calico pods in CrashLoop** | Check logs: `kubectl logs -n kube-system -l k8s-app=calico-kube-controllers`. Verify pod CIDR available |
| **Worker node join fails** | Verify control plane ready: `kubectl get nodes`. Check token valid: `kubeadm token list` |

**Debug Provisioning:**
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

## Notes

- **Development Only**: For production, implement security policies and RBAC
- **Sensitive Data**: Never commit `configs/` directory to version control
- **Firewall**: Allow VM↔Host communication through firewall

