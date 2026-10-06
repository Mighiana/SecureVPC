variable "name" {
  description = "Name prefix applied to every security group."
  type        = string
}

variable "vpc_id" {
  description = "VPC that owns the security groups."
  type        = string
}

variable "admin_cidrs" {
  description = "Source CIDRs allowed to SSH to the bastion."
  type        = list(string)
}
