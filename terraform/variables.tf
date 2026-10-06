# ---------------------------------------------------------------------------
# General
# ---------------------------------------------------------------------------

variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"
}

variable "project_name" {
  description = "Short project identifier used in resource names."
  type        = string
  default     = "securevpc"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.project_name))
    error_message = "project_name must be 2-21 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment label (e.g. lab, dev). Used in names and tags."
  type        = string
  default     = "lab"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,10}$", var.environment))
    error_message = "environment must be 2-11 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "extra_tags" {
  description = "Additional tags merged into the provider default_tags (e.g. Owner, CostCenter)."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

variable "vpc_cidr" {
  description = "IPv4 CIDR for the VPC."
  type        = string
  default     = "10.0.0.0/16"

  validation {
    condition     = can(cidrnetmask(var.vpc_cidr))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}

variable "public_subnet_cidr" {
  description = "IPv4 CIDR for the public subnet. Must sit inside vpc_cidr."
  type        = string
  default     = "10.0.1.0/24"

  validation {
    condition     = can(cidrnetmask(var.public_subnet_cidr))
    error_message = "public_subnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "private_subnet_cidr" {
  description = "IPv4 CIDR for the private subnet. Must sit inside vpc_cidr."
  type        = string
  default     = "10.0.2.0/24"

  validation {
    condition     = can(cidrnetmask(var.private_subnet_cidr))
    error_message = "private_subnet_cidr must be a valid IPv4 CIDR block."
  }
}

variable "availability_zone" {
  description = "AZ for both subnets. Null picks the first available AZ in the region."
  type        = string
  default     = null
}

# ---------------------------------------------------------------------------
# Access
# ---------------------------------------------------------------------------

variable "admin_cidrs" {
  description = "IPv4 CIDRs allowed to SSH to the bastion (e.g. [\"203.0.113.10/32\"]). No default on purpose."
  type        = list(string)

  validation {
    condition     = length(var.admin_cidrs) > 0 && length(var.admin_cidrs) <= 5
    error_message = "Provide between 1 and 5 admin CIDRs."
  }

  validation {
    condition     = alltrue([for c in var.admin_cidrs : can(cidrnetmask(c))])
    error_message = "Every admin_cidrs entry must be a valid IPv4 CIDR (e.g. 203.0.113.10/32)."
  }

  validation {
    condition     = alltrue([for c in var.admin_cidrs : try(tonumber(split("/", c)[1]) >= 16, false)])
    error_message = "admin_cidrs entries must be /16 or narrower. Opening SSH to 0.0.0.0/0 (or any very wide range) is refused."
  }
}

variable "ssh_public_key" {
  description = "OpenSSH public key (contents, not a path) for ec2-user on both instances. Generate locally; the private key never enters Terraform state."
  type        = string

  validation {
    condition     = can(regex("^(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp(256|384|521)) [A-Za-z0-9+/=]+( .*)?$", trimspace(var.ssh_public_key)))
    error_message = "ssh_public_key must be an OpenSSH public key line (ssh-ed25519 / ssh-rsa / ecdsa-sha2-*)."
  }
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------

variable "instance_type" {
  description = "EC2 instance type for the bastion and the web server."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Root EBS volume size (GiB) for each instance."
  type        = number
  default     = 8

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 50
    error_message = "root_volume_size must be between 8 and 50 GiB."
  }
}

variable "ami_ssm_parameter" {
  description = "Public SSM parameter that resolves the AMI ID. Defaults to the latest Amazon Linux 2023 x86_64 image."
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

variable "flow_logs_traffic_type" {
  description = "Which flows to capture: ACCEPT, REJECT or ALL."
  type        = string
  default     = "ALL"

  validation {
    condition     = contains(["ACCEPT", "REJECT", "ALL"], var.flow_logs_traffic_type)
    error_message = "flow_logs_traffic_type must be ACCEPT, REJECT or ALL."
  }
}

variable "flow_logs_retention_days" {
  description = "CloudWatch Logs retention for flow log records."
  type        = number
  default     = 14

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.flow_logs_retention_days)
    error_message = "flow_logs_retention_days must be a value accepted by CloudWatch Logs (1, 3, 5, 7, 14, 30, 60, 90, ...)."
  }
}

variable "flow_logs_aggregation_interval" {
  description = "Flow log aggregation window in seconds. 60 gives faster visibility; 600 is the AWS default."
  type        = number
  default     = 60

  validation {
    condition     = contains([60, 600], var.flow_logs_aggregation_interval)
    error_message = "flow_logs_aggregation_interval must be 60 or 600."
  }
}

variable "enable_kms_encryption" {
  description = "Encrypt flow logs with a customer-managed KMS key (about USD 1/month per key)."
  type        = bool
  default     = true
}

variable "enable_s3_flow_log_archive" {
  description = "Additionally deliver flow logs to an S3 bucket (Parquet, hourly partitions)."
  type        = bool
  default     = false
}

variable "s3_archive_expiration_days" {
  description = "Delete archived flow log objects after this many days."
  type        = number
  default     = 30

  validation {
    condition     = var.s3_archive_expiration_days >= 1
    error_message = "s3_archive_expiration_days must be at least 1."
  }
}

variable "s3_archive_force_destroy" {
  description = "Let terraform destroy empty and delete the archive bucket. Keep true for a lab so teardown is complete."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Cost guardrail
# ---------------------------------------------------------------------------

variable "budget_alert_email" {
  description = "If set, creates an AWS Budget that emails this address at 80% actual / 100% forecast of monthly_budget_usd."
  type        = string
  default     = null
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget (USD) used when budget_alert_email is set."
  type        = number
  default     = 20
}
