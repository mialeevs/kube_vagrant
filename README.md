# Kubernetes Installation on Ubuntu 22.04 with VAGRANT

## For Linux OS / Windows 10/11 OS

### Install VMware Workstation(VMware destop plugin) ,Vagrant and Git

Install VMWare, Vagrant and Git on the laptop or PC

> [VMWare Workstation](https://access.broadcom.com/default/ui/v1/signin/)

> [Vagrant](https://www.vagrantup.com/)

> [GIT](https://git-scm.com/)

> [VMWare Desktop Plugin](https://developer.hashicorp.com/vagrant/docs/providers/vmware/vagrant-vmware-utility)


Install the required plugins for vmwaredesktop

```bash
vagrant plugin install vagrant-vmware-desktop
vagrant plugin install vagrant-hostmanager
```

### Clone the repository

Clone the repo to the desired location

```bash
git clone https://github.com/mialeevs/kube_vagrant.git
cd kube_vagrant

# Update the settings.yaml file for desired worker node count and run below command.
# Update the same file for memory and cpu allocation for the cp and worker nodes as needed.
vagrant up
```
