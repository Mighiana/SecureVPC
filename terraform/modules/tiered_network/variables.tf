variable "name" {
  description = "Name prefix applied to every network resource."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR. Must be a /16; every tier is carved from it with cidrsubnet()."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0)) && endswith(var.vpc_cidr, "/16")
    error_message = "vpc_cidr must be a valid /16."
  }
}

variable "azs" {
  description = "Availability Zones to spread every tier across (2 or 3)."
  type        = list(string)

  validation {
    condition     = length(var.azs) >= 2 && length(var.azs) <= 3 && length(distinct(var.azs)) == length(var.azs)
    error_message = "Provide 2 or 3 distinct Availability Zones."
  }
}

variable "enable_nat_gateway" {
  description = "Create NAT Gateway(s) for app-tier internet egress. Off when nothing outside AWS needs to be reached."
  type        = bool
}

variable "single_nat_gateway" {
  description = "Use one NAT Gateway for all AZs (cheaper, but egress fails if that AZ fails)."
  type        = bool
}

variable "enable_firewall_subnets" {
  description = "Create dedicated firewall subnets and leave the public default route to the network_firewall module."
  type        = bool
}

variable "data_port" {
  description = "TCP port the data tier listens on (only reachable from the app tier)."
  type        = number
}
