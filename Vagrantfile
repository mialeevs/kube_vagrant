
require "yaml"
settings = YAML.load_file "settings.yaml"

NUM_WORKER_NODES = settings["nodes"]["workers"]["count"]

Vagrant.configure("2") do |config|

  if `uname -m`.strip == "aarch64"
    config.vm.box = settings["software"]["box"] + "-arm64"
  else
    config.vm.box = settings["software"]["box"]
  end
  config.vm.box_version = "202407.23.0"
  config.vm.box_check_update = true
  

  config.vm.define "control-plane" do |control|
    control.vm.hostname = "master-node"
    if settings["shared_folders"]
      settings["shared_folders"].each do |shared_folder|
        control.vm.synced_folder shared_folder["host_path"], shared_folder["vm_path"]
      end
    end
   control.vm.provider "vmware_desktop" do |vb|
        vb.vmx["memsize"] = settings["nodes"]["control"]["memory"]
        vb.vmx["numvcpus"] = settings["nodes"]["control"]["cpu"]
        # vb.gui = true
        vb.ssh_info_public = true
    end
    control.vm.provision "shell",
      env: {
        "DNS_SERVERS" => settings["network"]["dns_servers"].join(" "),
        "ENVIRONMENT" => settings["environment"],
        "CRIO_VERSION" => settings["software"]["crio"],
        "KUBERNETES_VERSION" => settings["software"]["kubernetes"],
        "OS" => settings["software"]["os"]
      },
      path: "scripts/common.sh"
    control.vm.provision "shell",
      env: {
        "CALICO_VERSION" => settings["software"]["calico"],
        "CRIO_VERSION" => settings["software"]["crio"],
        "CONTROL_IP" => settings["network"]["control_ip"],
        "POD_CIDR" => settings["network"]["pod_cidr"],
        "SERVICE_CIDR" => settings["network"]["service_cidr"]
      },
      path: "scripts/control.sh"
  end

  (1..NUM_WORKER_NODES).each do |i|

    config.vm.define "node0#{i}" do |node|
      node.vm.hostname = "worker-node0#{i}"
      if settings["shared_folders"]
        settings["shared_folders"].each do |shared_folder|
          node.vm.synced_folder shared_folder["host_path"], shared_folder["vm_path"]
        end
      end
      node.vm.provider "vmware_desktop" do |vb|
          vb.vmx["memsize"] = settings["nodes"]["workers"]["memory"]
          vb.vmx["numvcpus"] = settings["nodes"]["workers"]["cpu"]
          # vb.gui = true
          vb.ssh_info_public = true
      end
      node.vm.provision "shell",
        env: {
          "DNS_SERVERS" => settings["network"]["dns_servers"].join(" "),
          "ENVIRONMENT" => settings["environment"],
          "KUBERNETES_VERSION" => settings["software"]["kubernetes"],
          "CRIO_VERSION" => settings["software"]["crio"],
          "OS" => settings["software"]["os"]
        },
        path: "scripts/common.sh"
      node.vm.provision "shell", path: "scripts/node.sh"

    end

  end
end 
