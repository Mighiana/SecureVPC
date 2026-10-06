variable "name" {
  description = "Name prefix for the Athena workgroup and Glue database."
  type        = string
}

variable "bucket_name" {
  description = "S3 bucket holding the Parquet flow logs (Hive-compatible, per-hour partitions)."
  type        = string
}

variable "account_id" {
  description = "AWS account ID (part of the flow log S3 prefix)."
  type        = string
}

variable "region" {
  description = "AWS region (part of the flow log S3 prefix)."
  type        = string
}

variable "fields" {
  description = "Flow log fields, in the order of the S3 flow log's custom log_format."
  type        = list(string)
}

variable "kms_key_arn" {
  description = "KMS key for Athena query results (null = SSE-S3)."
  type        = string
}

variable "bytes_scanned_cutoff" {
  description = "Per-query scan limit in bytes; Athena cancels queries above it (cost guard)."
  type        = number
}
