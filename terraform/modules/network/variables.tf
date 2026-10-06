variable "name" {
  description = "Name prefix applied to every network resource."
  type        = string
}

variable "vpc_cidr" {
  description = "IPv4 CIDR block for the VPC."
  type        = string
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet (bastion host + NAT Gateway)."
  type        = string
}

variable "private_subnet_cidr" {
  description = "CIDR for the private subnet (web server, no public IPs)."
  type        = string
}

variable "availability_zone" {
  description = "Availability Zone used for both subnets."
  type        = string
}

variable "admin_cidrs" {
  description = "Source CIDRs allowed to reach the bastion on TCP/22 at the NACL layer."
  type        = list(string)
}
