variable "adminUserName" {
  description = "admin user name from vault"
  type = string
}

variable "adminPassword" {
  description = "Password for admin user"
  type = string
}

variable "rootUserName" {
  description = "Root User"
  type = string
}

variable "rootPassword" {
  description = "password for root user"
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