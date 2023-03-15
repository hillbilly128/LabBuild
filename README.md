# LabBuild

## Intro
This project was written to build a number of Proxmox hosts using libvirt on the local machine. I wrote this to build a number of hosts for when I wanted to play with Terraform and Ansible without using cloud hosting.

## How it works
Once it was the number of hosts your require, either supplied externally or prompted once ran, it sets up a storage pool as a working area in a predefined location. Then downloads the current debian bullseye image and build the correct number of host root drives and cloud init images.

### Network
Each host has 2 network interfaces, one with a dynamically IP address that uses the default Libvirt bridge to access the internet. This will also be the connection for the hosted VMs bridge. The second network connection is for the host to virtual host connection and for the clustering between hosts. This interface has a statically assigned IP address.

### Storage
Each virtal host has 2 drives, a main root drive that is built from the current Debian Bullseye image, and a second data drive that is planned to host the VM images. This will also be used to host a Gluster Drive that is shared accross the hosts.

## To run
To run this is use a couple of bash scripts to set some environment variables for accessing my bitwarden vault and then call the Terraform commands

The create script looks like this.

```console
#!/bin/sh
clear
export TF_VAR_bw_client_id=<Bitwarden Client ID>
export TF_VAR_bw_client_secret=<Bitwarden Client Secret>
export TF_VAR_bw_password=<Bitwarden password>
export TF_LOG=INFO
export TF_LOG_PATH="./tfbuild.log"
echo "Backing up log"
mv tfbuild.log tfbuild.log.bak -fu
terraform init
echo ""
terraform validate
echo ""
terraform plan -out=create.plan
echo ""
terraform apply -parallelism=3 create.plan 
echo ""
```

The destroy script looks like this.

```console
#!/bin/sh
clear
export TF_VAR_bw_client_id=<Bitwarden Client ID>
export TF_VAR_bw_client_secret=<Bitwarden Client Secret>
export TF_VAR_bw_password=<Bitwarden password>
export TF_LOG=INFO
export TF_LOG_PATH="./tfdestroy.log"
echo "Backing up log"
mv tfdestroy.log tfdestroy.log.bak -fu
terraform init
echo ""
terraform validate
echo ""
terraform plan -destroy -out=destroy.plan
echo ""
terraform apply -destroy destroy.plan
```

## Notes
In order to get the networking to come up after Proxmox-VE is installed, a double reboot is required. This is acheived by installing a Systemd service and a reboot script. Once the system has rebooted from the ansible command, the script carries out the second reboot, disabling the Service before it reboots the system. Once rebooted and back in touch with ansible, the service and scripts are removed.