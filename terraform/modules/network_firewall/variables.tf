variable "name" {
  description = "Name prefix applied to every firewall resource."
  type        = string
}

variable "vpc_id" {
  description = "VPC the firewall protects."
  type        = string
}

variable "vpc_cidr" {
  description = "VPC CIDR, used as HOME_NET in the Suricata rules."
  type        = string
}

variable "firewall_subnet_ids" {
  description = "Dedicated firewall subnet IDs keyed by AZ (one endpoint per AZ)."
  type        = map(string)
}

variable "firewall_route_table_id" {
  description = "Route table shared by the firewall subnets."
  type        = string
}

variable "public_route_table_ids" {
  description = "Public route table IDs keyed by AZ; their default route is pointed at the same-AZ firewall endpoint."
  type        = map(string)
}

variable "public_subnet_cidrs" {
  description = "Public subnet CIDRs keyed by AZ; the IGW edge route table sends traffic for them through the firewall."
  type        = map(string)
}

variable "igw_id" {
  description = "Internet Gateway ID."
  type        = string
}

variable "egress_allowed_domains" {
  description = "Domains the VPC may reach over HTTP/HTTPS (subdomains included). Empty = no internet egress."
  type        = list(string)
}

variable "managed_rule_groups" {
  description = "AWS managed stateful rule group names (StrictOrder variants), evaluated before the custom rules."
  type        = list(string)
}

variable "kms_key_arn" {
  description = "Customer-managed KMS key for firewall, policy, rule group and log encryption."
  type        = string
}

variable "alert_log_group_name" {
  description = "CloudWatch log group for ALERT logs (drops and alerts)."
  type        = string
}

variable "flow_log_group_name" {
  description = "CloudWatch log group for FLOW logs (every inspected flow)."
  type        = string
}

variable "log_retention_days" {
  description = "Retention for the firewall log groups."
  type        = number
}

variable "delete_protection" {
  description = "Block deletion of the firewall (turn on for long-lived environments)."
  type        = bool
}

variable "region" {
  description = "AWS region (used in managed rule group ARNs)."
  type        = string
}

variable "partition" {
  description = "AWS partition."
  type        = string
}
