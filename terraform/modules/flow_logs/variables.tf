variable "name" {
  description = "Name prefix applied to every logging resource."
  type        = string
}

variable "vpc_id" {
  description = "VPC whose traffic is captured."
  type        = string
}

variable "traffic_type" {
  description = "Flow log traffic type: ACCEPT, REJECT or ALL."
  type        = string
}

variable "retention_in_days" {
  description = "CloudWatch Logs retention for flow log records."
  type        = number
}

variable "max_aggregation_interval" {
  description = "Flow log aggregation window in seconds (60 or 600)."
  type        = number
}

variable "enable_kms" {
  description = "Encrypt the CloudWatch log group (and the S3 bucket, if enabled) with a customer-managed KMS key."
  type        = bool
}

variable "enable_s3_archive" {
  description = "Also deliver flow logs to an S3 bucket for long-term/cheap archive."
  type        = bool
}

variable "s3_expiration_days" {
  description = "Days after which archived flow log objects in S3 are deleted."
  type        = number
}

variable "s3_force_destroy" {
  description = "Allow terraform destroy to delete the archive bucket even if it contains objects."
  type        = bool
}

variable "account_id" {
  description = "AWS account ID (used to scope IAM trust and KMS key policies)."
  type        = string
}

variable "region" {
  description = "AWS region (used to scope the KMS key policy)."
  type        = string
}

variable "partition" {
  description = "AWS partition (aws, aws-cn, aws-us-gov)."
  type        = string
}

variable "s3_log_format" {
  description = "Custom record format for the S3 flow log (null = AWS default v2 fields)."
  type        = string
  default     = null
}

variable "s3_hive_compatible_partitions" {
  description = "Write S3 flow logs with Hive-style key=value prefixes (for Athena partition projection)."
  type        = bool
  default     = false
}
