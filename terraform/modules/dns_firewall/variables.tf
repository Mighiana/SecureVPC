variable "name" {
  description = "Name prefix applied to every DNS Firewall resource."
  type        = string
}

variable "vpc_id" {
  description = "VPC whose Route 53 Resolver queries are filtered and logged."
  type        = string
}

variable "allowed_domains" {
  description = "Domains (and their subdomains) the VPC may resolve when block_unlisted is true."
  type        = list(string)
}

variable "managed_domain_list_ids" {
  description = "AWS Managed Domain List IDs to block (malware, botnet, aggregate threat). Region-specific; see README."
  type        = list(string)
}

variable "block_unlisted" {
  description = "Walled garden: answer NXDOMAIN for every domain not in allowed_domains."
  type        = bool
}

variable "fail_open" {
  description = "Let queries through if DNS Firewall is impaired. False = fail closed."
  type        = bool
}

variable "query_log_group_name" {
  description = "CloudWatch log group for Resolver query logs."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key for the query log group."
  type        = string
}

variable "log_retention_days" {
  description = "Retention for the query log group."
  type        = number
}
