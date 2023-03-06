terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "0.7.1"
    }
    bitwarden = {
      source  = "maxlaverse/bitwarden"
      version = ">= 0.5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "3.4.3"
    }
    local = {
      source  = "hashicorp/local"
      version = "2.3.0"
    }
    null = {
      source  = "hashicorp/null"
      version = "3.2.1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "4.0.4"
    }
  }
}

provider "bitwarden" {
  master_password = var.bw_password
  client_id       = var.bw_client_id
  client_secret   = var.bw_client_secret
  email           = "craig.hillbeck@gmail.com"
  server          = "https://vault.bitwarden.com"
}

provider "libvirt" {
  uri = "qemu:///system"
}

resource "tls_private_key" "dev_key" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "local_sensitive_file" "ssh-private-key" {
  filename        = "${abspath(path.root)}/.ssh/dev_rsa"
  file_permission = 0400
  content         = tls_private_key.dev_key.private_key_openssh
}

data "bitwarden_item_login" "proxmox-host-credentials" {
  id = "b0243597-acea-4f1f-8827-afa301543ae8"
}

data "bitwarden_item_login" "admin-root-credentials" {
  id = "7523cbb5-6184-46df-9069-afa301546588"
}

variable "host-quantity" {
  type        = number
  description = "Number of hosts required"
}

variable "domain-name" {
  type        = string
  description = "Domain Name for the Hosts"
  default     = "test.local"
}

resource "random_integer" "rng" {
  count = (var.host-quantity * 3)
  min   = 0
  max   = 255

  depends_on = [
    var.host-quantity
  ]
}


locals {
  random_mac_bytes   = flatten([for r in range(0, var.host-quantity) : [for i in range(0, 3) : format("%.2x", random_integer.rng[(r * 3) + i].result)]])
  random_mac         = [for r in range(0, var.host-quantity) : "52:54:00:${local.random_mac_bytes[0 + (r * 3)]}:${local.random_mac_bytes[1 + (r * 3)]}:${local.random_mac_bytes[2 + (r * 3)]}"]
  random_mac_cluster = [for r in range(0, var.host-quantity) : "52:54:00:${local.random_mac_bytes[1 + (r * 3)]}:${local.random_mac_bytes[1 + (r * 3)]}:${local.random_mac_bytes[2 + (r * 3)]}"]
  hostnames          = [for i in range(0, var.host-quantity) : "host${i + 1}.${var.domain-name}"]
}

resource "local_file" "variables" {
  content  = "host-quantity = ${var.host-quantity}\ndomain-name = \"${var.domain-name}\""
  filename = "${path.module}/build.auto.tfvars"
}

#Build a pool to hold the template cloud debian image
resource "libvirt_pool" "debian10Pool" {
  name = "debian10-pool"
  type = "dir"
  path = "/mnt/store/Library/DiskImage/templates/"


}

#Build a blank thin provisioned HDD 
resource "libvirt_volume" "data" {
  count = var.host-quantity
  name  = "Host-data-${count.index}.qcow2"
  pool  = libvirt_pool.debian10Pool.name
  size  = 536870912000

  depends_on = [
    libvirt_pool.debian10Pool
  ]
}

#Fetch the current Debian 10 cloud init image
resource "libvirt_volume" "debian10image" {
  name   = "debian10-image.qcow2"
  pool   = libvirt_pool.debian10Pool.name
  source = "https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-genericcloud-amd64.qcow2"
  format = "qcow2"

  depends_on = [
    libvirt_pool.debian10Pool
  ]
}

#Clone the Debian 11 image for each host
resource "libvirt_volume" "host_root_disk" {
  count          = var.host-quantity
  name           = "host_root_${count.index}.qcow2"
  pool           = libvirt_pool.debian10Pool.name
  base_volume_id = libvirt_volume.debian10image.id
  size           = 12884901888

  depends_on = [
    libvirt_volume.debian10image
  ]
}

#Meta data for each host
data "template_file" "meta_data" {
  count    = var.host-quantity
  template = yamlencode({ instance-id : local.hostnames[count.index], local-hostname : local.hostnames[count.index] })
}

#Standard user data for all hosts
data "template_file" "user_data" {
  count    = var.host-quantity
  template = <<-EOL
  #cloud-config

  manage_etc_hosts: false

  timezone: Europe/London

  runcmd:
    - 'wget https://enterprise.proxmox.com/debian/proxmox-release-bullseye.gpg -O /etc/apt/trusted.gpg.d/proxmox-release-bullseye.gpg'

  ntp:
    enabled: true
    ntp_client: chrony
    pools: [0.uk.pool.ntp.org,1.uk.pool.ntp.org,2.uk.pool.ntp.org,4.uk.pool.ntp.org]

  apt:
    security:
    - arches: default
      uri: http://security.debian.org/debian-security
  
    
    sources_list: |
      deb $MIRROR $RELEASE main contrib
      deb-src $MIRROR $RELEASE main contrib
      deb $SECURITY $RELEASE-security main contrib non-free

  fqdn: ${local.hostnames[count.index]}
  hostname: ${trim(local.hostnames[count.index], var.domain-name)}
  prefer_fqdn_over_hostname: true

  users:
  - name: ${data.bitwarden_item_login.admin-root-credentials.username}
    plain_text_passwd: ${data.bitwarden_item_login.admin-root-credentials.password}
    shell: /bin/bash
    lock_passwd: false
    ssh_authorized_keys: 
    - ${trimspace(tls_private_key.dev_key.public_key_openssh)}
    sudo: ALL=(ALL) NOPASSWD:ALL
  EOL

  depends_on = [
    data.bitwarden_item_login.admin-root-credentials
  ]
}

#Network file for each host
data "template_file" "network_config" {
  count    = var.host-quantity
  template = yamlencode({ "network" : { "version" : 2, "ethernets" : { "eth0" : { "dhcp4" : true, "match" : { "macaddress" : local.random_mac[count.index] } }, "eth1" : { "addressess" : ["172.16.10.${10 + count.index}/24"], "mtu" : 9000, "match" : { "macaddress" : local.random_mac_cluster[count.index] } } } } })
}

data "libvirt_network_dns_host_template" "hosts" {
  count    = var.host-quantity
  ip       = "172.16.10.${10 + count.index}"
  hostname = local.hostnames[count.index]
}

resource "libvirt_network" "network_cluster" {
  name      = "cluster-terra"
  mode      = "none"
  autostart = true
  mtu       = 9000
  addresses = ["172.16.10.0/24"]
  dns {
    local_only = true
  }
  dhcp {
    enabled = false
  }
}

resource "libvirt_cloudinit_disk" "commoninit" {
  count          = var.host-quantity
  name           = "commoninit${count.index}.iso"
  user_data      = data.template_file.user_data[count.index].rendered
  meta_data      = data.template_file.meta_data[count.index].rendered
  network_config = data.template_file.network_config[count.index].rendered
  pool           = libvirt_pool.debian10Pool.name

  depends_on = [
    data.template_file.meta_data, data.template_file.user_data, data.template_file.network_config
  ]
}

# Create the machine
resource "libvirt_domain" "host" {
  count    = var.host-quantity
  name     = local.hostnames[count.index]
  memory   = "2048"
  vcpu     = 2
  emulator = "/usr/bin/qemu-system-x86_64"
  machine  = "pc-i440fx-6.2"
  arch     = "x86_64"

  cpu {
    mode = "host-model"
  }

  cloudinit = libvirt_cloudinit_disk.commoninit[count.index].id

  #internet network interface using default NAT'd network
  network_interface {
    network_name   = "default"
    hostname       = local.hostnames[count.index]
    mac            = local.random_mac[count.index]
    wait_for_lease = true
  }

  #privtae network interface using generated network
  network_interface {
    network_id = libvirt_network.network_cluster.id
    hostname   = local.hostnames[count.index]
    addresses  = ["172.16.10.${10 + count.index}"]
    mac        = local.random_mac_cluster[count.index]
  }

  # IMPORTANT: this is a known bug on cloud images, since they expect a console
  # we need to pass it
  # https://bugs.launchpad.net/cloud-images/+bug/1573095
  console {
    type        = "pty"
    target_port = "0"
    target_type = "serial"
  }

  console {
    type        = "pty"
    target_type = "virtio"
    target_port = "1"
  }

  disk {
    volume_id = libvirt_volume.host_root_disk[count.index].id
    scsi      = true
  }

  disk {
    volume_id = libvirt_volume.data[count.index].id
    scsi      = true
  }

  #disk {
  #  volume_id = split(";",libvirt_cloudinit_disk.commoninit[count.index].id)[0]
  #  scsi = true
  #}

  graphics {
    type        = "spice"
    listen_type = "address"
    autoport    = true
  }

  #xml {
  #  xslt = file("${path.module}/nodes-adjust.xslt")
  #}

  connection {
    type        = "ssh"
    host        = "172.16.10.${10 + count.index}"
    user        = data.bitwarden_item_login.admin-root-credentials.username
    private_key = tls_private_key.dev_key.private_key_openssh
    timeout     = "2m"
    agent       = false
  }

  provisioner "remote-exec" {
    inline = [
      "echo 172.16.10.${10 + count.index}\t${local.hostnames[count.index]}\t${trim(local.hostnames[count.index], var.domain-name)} | sudo tee -a /etc/hosts"
    ]
  }

  provisioner "local-exec" {
    working_dir = "./ansible/"
    command     = "ANSIBLE_HOST_KEY_CHECKING=FALSE ansible-playbook -vvvv -u ${data.bitwarden_item_login.admin-root-credentials.username} --key-file ${local_sensitive_file.ssh-private-key.filename} -i 172.16.10.${10 + count.index}, buildProxmox.yaml"
  }

  depends_on = [
    libvirt_volume.host_root_disk, libvirt_cloudinit_disk.commoninit, libvirt_network.network_cluster
  ]
}

#null-resource hack to clean up known hosts file on destroy
resource "null_resource" "known_hosts" {
  count = var.host-quantity
  provisioner "local-exec" {
    when       = destroy
    command    = "ssh-keygen -f ~/.ssh/known_hosts -R 172.16.10.${10 + count.index}"
    on_failure = continue
  }
}

output "Host-details" {
  value = libvirt_domain.host
}

output "macaddress" {
  value = setunion(local.random_mac, local.random_mac_cluster)
}
