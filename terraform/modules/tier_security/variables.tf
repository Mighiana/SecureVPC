variable "name" {
  description = "Name prefix applied to every security group."
  type        = string
}

variable "vpc_id" {
  description = "VPC the security groups belong to."
  type        = string
}

variable "region" {
  description = "AWS region (used to look up the S3 managed prefix list)."
  type        = string
}

variable "alb_ingress_cidrs" {
  description = "CIDRs allowed to reach the ALB listeners."
  type        = list(string)
}

variable "enable_https" {
  description = "Open TCP/443 on the ALB (set when an ACM certificate is configured)."
  type        = bool
}

variable "allow_internet_egress" {
  description = "Let the app tier open HTTP/HTTPS to the internet (via NAT; the firewall still enforces the domain allowlist)."
  type        = bool
}

variable "data_port" {
  description = "TCP port of the data tier."
  type        = number
}
