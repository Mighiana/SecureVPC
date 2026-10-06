variable "name" {
  description = "Name prefix applied to every compute resource."
  type        = string
}

variable "ami_id" {
  description = "AMI used for both instances (Amazon Linux 2023 by default, resolved in the root module)."
  type        = string
}

variable "instance_type" {
  description = "EC2 instance type for the bastion and the web server."
  type        = string
}

variable "public_subnet_id" {
  description = "Subnet for the bastion host."
  type        = string
}

variable "private_subnet_id" {
  description = "Subnet for the web server."
  type        = string
}

variable "bastion_sg_id" {
  description = "Security group attached to the bastion host."
  type        = string
}

variable "web_sg_id" {
  description = "Security group attached to the web server."
  type        = string
}

variable "ssh_public_key" {
  description = "OpenSSH public key installed on both instances. The private key never touches Terraform."
  type        = string
}

variable "root_volume_size" {
  description = "Root EBS volume size in GiB."
  type        = number
}
