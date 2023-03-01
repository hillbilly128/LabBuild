variable "bw_client_id" {
  type        = string
  description = "Bitwarden Client ID"
  sensitive   = true
}

variable "bw_client_secret" {
  type        = string
  description = "Bitwarden Client Secret"
  sensitive   = true
}

variable "bw_password" {
  type        = string
  description = "Bitwarden Master Key"
  sensitive   = true
}

/*variable "vms" {
  description = "Hold the details of all of the VMs and LXC containers to be created"
  type = list(object({
    description  = string
    ip0gw        = string
    ip0          = string
    ip0cidr      = number
    name         = string
    cores        = number
    sockets      = number
    memory       = number
    disksize     = number
    disksizeunit = string
    purpose      = string
    bootorder    = number
    domain       = number
    type         = string
  }))
}

variable "domains" {
  type = list(object({
    domainname  = string
    nameservers = string
  }))
}

locals {
  lxc = {
    for vm in var.vms : vm.name => vm
    if vm.type == "lxc"
  }

  qemu = {
    for vm in var.vms : vm.name => vm
    if vm.type == "vm"
  }

  proxmox_host = "172.16.10.10" //The initial proxmox host to start
}*/