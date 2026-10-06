variable "name" {
  description = "Name prefix applied to every web-tier resource."
  type        = string
}

variable "vpc_id" {
  description = "VPC ID."
  type        = string
}

variable "region" {
  description = "AWS region."
  type        = string
}

variable "partition" {
  description = "AWS partition."
  type        = string
}

variable "account_id" {
  description = "AWS account ID."
  type        = string
}

variable "ami_id" {
  description = "AMI for the app instances (Amazon Linux 2023)."
  type        = string
}

variable "instance_type" {
  description = "Instance type for the app tier."
  type        = string
}

variable "root_volume_size" {
  description = "Root volume size in GiB."
  type        = number
}

variable "public_subnet_ids" {
  description = "Public subnets for the ALB (one per AZ)."
  type        = list(string)
}

variable "app_subnet_ids" {
  description = "Private app subnets for the Auto Scaling group."
  type        = list(string)
}

variable "alb_sg_id" {
  description = "Security group for the ALB."
  type        = string
}

variable "app_sg_id" {
  description = "Security group for the app instances."
  type        = string
}

variable "asg_min_size" {
  description = "Minimum number of app instances."
  type        = number
}

variable "asg_desired_capacity" {
  description = "Desired number of app instances."
  type        = number
}

variable "asg_max_size" {
  description = "Maximum number of app instances."
  type        = number
}

variable "certificate_arn" {
  description = "ACM certificate for an HTTPS listener. Null = HTTP only."
  type        = string
}

variable "web_hostname" {
  description = "Hostname covered by certificate_arn and mapped (CNAME/alias) to the ALB; used for web_url when HTTPS is on."
  type        = string
  default     = null
}

variable "waf_rate_limit" {
  description = "Requests per 5 minutes per client IP before WAF blocks it."
  type        = number
}

variable "waf_log_group_name" {
  description = "CloudWatch log group for WAF logs (must start with aws-waf-logs-)."
  type        = string
}

variable "session_log_group_name" {
  description = "CloudWatch log group for SSM Session Manager transcripts."
  type        = string
}

variable "kms_key_arn" {
  description = "KMS key for log groups and session encryption."
  type        = string
}

variable "log_retention_days" {
  description = "Retention for the WAF and session log groups."
  type        = number
}

variable "alb_logs_expiration_days" {
  description = "Days before ALB access logs are deleted from S3."
  type        = number
}

variable "force_destroy" {
  description = "Let terraform destroy delete the ALB log bucket with its objects."
  type        = bool
}

variable "deletion_protection" {
  description = "Enable ALB deletion protection."
  type        = bool
}
