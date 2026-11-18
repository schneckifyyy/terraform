variable "region" {
  description = "AWS-Region (Learner Lab: us-east-1 oder us-west-2)"
  type        = string
  default     = "us-east-1"
}

variable "availability_zone" {
  description = "Availability Zone des Subnetzes"
  type        = string
  default     = "us-east-1a"
}

variable "vpc_cidr" {
  type    = string
  default = "10.0.0.0/16"
}

variable "subnet_cidr" {
  type    = string
  default = "10.0.1.0/24"
}

variable "team_ips" {
  description = "Öffentliche IPs der Teamgeräte als /32 (SSH, GitLab-Web-UI), z. B. [\"203.0.113.7/32\"]"
  type        = list(string)

  validation {
    condition     = length(var.team_ips) > 0 && alltrue([for c in var.team_ips : can(cidrhost(c, 0))])
    error_message = "team_ips muss mindestens eine gültige CIDR-Adresse enthalten, z. B. 203.0.113.7/32."
  }
}

variable "ssh_public_keys" {
  description = "Öffentliche SSH-Schlüssel aller Teammitglieder (Inhalt von id_ed25519.pub)"
  type        = list(string)

  validation {
    condition     = length(var.ssh_public_keys) > 0
    error_message = "Mindestens ein öffentlicher SSH-Schlüssel ist nötig, sonst kommt niemand auf die VMs."
  }
}

variable "use_custom_dhcp" {
  description = "false beim ersten Aufbau; true erst nach der BIND-Installation auf dns1/dns2"
  type        = bool
  default     = false
}
