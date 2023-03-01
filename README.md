# LabBuild

## Intro
Terraform project that builds a proxmox cluster automatically and configures them as a cluster with a Gluster Drive (or at least thats the plan)

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