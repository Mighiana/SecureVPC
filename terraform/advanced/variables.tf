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
    condition     = can(regex("^[a-z][a-z0-9-]{1,14}$", var.project_name))
    error_message = "project_name must be 2-15 chars of lowercase letters, digits or hyphens, starting with a letter."
  }
}

variable "environment" {
  description = "Environment label used in names and tags."
  type        = string
  default     = "adv"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,7}$", var.environment))
    error_message = "environment must be 2-8 chars of lowercase letters, digits or hyphens, starting with a letter."
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
  description = "VPC CIDR (/16). Tiers are carved from it; see modules/tiered_network."
  type        = string
  default     = "10.0.0.0/16"
}

variable "az_count" {
  description = "Number of AZs to use when availability_zones is empty."
  type        = number
  default     = 2

  validation {
    condition     = var.az_count >= 2 && var.az_count <= 3
    error_message = "az_count must be 2 or 3."
  }
}

variable "availability_zones" {
  description = "Explicit AZ names. Empty = first az_count available AZs."
  type        = list(string)
  default     = []
}

variable "single_nat_gateway" {
  description = "One NAT Gateway for all AZs (cheaper; egress depends on that AZ). Only used when egress_allowed_domains is non-empty."
  type        = bool
  default     = true
}

variable "data_port" {
  description = "TCP port of the (empty) data tier, e.g. 5432 for PostgreSQL."
  type        = number
  default     = 5432

  validation {
    condition     = var.data_port > 0 && var.data_port < 65536 && !contains([22, 3389], var.data_port)
    error_message = "data_port must be a valid TCP port other than 22 or 3389."
  }
}

# ---------------------------------------------------------------------------
# Egress control
# ---------------------------------------------------------------------------

variable "egress_allowed_domains" {
  description = "Internet domains (and subdomains) the app tier may reach over HTTP/HTTPS. Empty (default) = no internet egress and no NAT Gateway; AWS APIs and OS packages use VPC endpoints."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.egress_allowed_domains) <= 40
    error_message = "At most 40 egress domains (custom rule group capacity)."
  }

  validation {
    condition     = alltrue([for d in var.egress_allowed_domains : can(regex("^\\.?([a-z0-9-]+\\.)+[a-z]{2,}\\.?$", lower(d)))])
    error_message = "egress_allowed_domains entries must be plain domain names (no wildcards, schemes or paths)."
  }

  validation {
    condition     = length(var.egress_allowed_domains) == 0 || var.enable_network_firewall
    error_message = "egress_allowed_domains needs enable_network_firewall = true; without the firewall nothing enforces the allowlist."
  }
}

variable "enable_network_firewall" {
  description = "Deploy AWS Network Firewall between the IGW and the public subnets (largest cost item)."
  type        = bool
  default     = true
}

variable "network_firewall_managed_rule_groups" {
  description = "AWS managed stateful rule groups (StrictOrder variants) evaluated before the custom rules."
  type        = list(string)
  default = [
    "MalwareDomainsStrictOrder",
    "AbusedLegitMalwareDomainsStrictOrder",
    "BotNetCommandAndControlDomainsStrictOrder",
    "ThreatSignaturesBotnetStrictOrder",
    "ThreatSignaturesMalwareStrictOrder",
    "ThreatSignaturesEmergingEventsStrictOrder",
  ]

  validation {
    condition     = alltrue([for g in var.network_firewall_managed_rule_groups : endswith(g, "StrictOrder")])
    error_message = "The policy uses STRICT_ORDER, so managed rule groups must be the *StrictOrder variants."
  }
}

variable "firewall_delete_protection" {
  description = "Protect the Network Firewall from deletion (turn on for long-lived environments)."
  type        = bool
  default     = false
}

variable "enable_dns_firewall" {
  description = "Deploy Route 53 Resolver DNS Firewall with query logging."
  type        = bool
  default     = true
}

variable "dns_firewall_managed_domain_list_ids" {
  description = "AWS Managed Domain List IDs to block (rslvr-fdl-...). IDs differ per region; list them with `aws route53resolver list-firewall-domain-lists`."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for id in var.dns_firewall_managed_domain_list_ids : can(regex("^rslvr-fdl-[a-z0-9]+$", id))])
    error_message = "Managed domain list IDs look like rslvr-fdl-0123456789abcdef."
  }
}

variable "dns_firewall_block_unlisted" {
  description = "Walled-garden DNS: NXDOMAIN for anything that is not an AWS/internal name or in egress_allowed_domains."
  type        = bool
  default     = true
}

variable "dns_firewall_fail_open" {
  description = "Let DNS through if DNS Firewall is impaired. False = fail closed (more secure, less available)."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Web tier
# ---------------------------------------------------------------------------

variable "alb_ingress_cidrs" {
  description = "IPv4 CIDRs allowed to reach the ALB. Narrow this to your own IP for a private demo."
  type        = list(string)
  default     = ["0.0.0.0/0"]

  validation {
    condition     = length(var.alb_ingress_cidrs) > 0 && alltrue([for c in var.alb_ingress_cidrs : can(cidrnetmask(c))])
    error_message = "alb_ingress_cidrs must be a non-empty list of valid IPv4 CIDRs."
  }
}

variable "certificate_arn" {
  description = "ACM certificate ARN for an HTTPS listener (HTTP then redirects to HTTPS). Null = HTTP only."
  type        = string
  default     = null

  validation {
    condition     = var.certificate_arn == null || can(regex("^arn:aws[a-z-]*:acm:", var.certificate_arn))
    error_message = "certificate_arn must be an ACM certificate ARN."
  }
}

variable "web_hostname" {
  description = "Hostname covered by certificate_arn (e.g. demo.example.com). Point it at the ALB with a CNAME/alias; web_url then uses it."
  type        = string
  default     = null

  validation {
    condition     = var.web_hostname == null || can(regex("^([a-z0-9-]+\\.)+[a-z]{2,}$", var.web_hostname))
    error_message = "web_hostname must be a plain DNS name such as demo.example.com."
  }

  validation {
    condition     = var.certificate_arn == null || var.web_hostname != null
    error_message = "Set web_hostname when certificate_arn is set; the certificate cannot cover the ALB's generated DNS name."
  }
}

variable "waf_rate_limit" {
  description = "Requests per 5 minutes from one IP before WAF blocks it."
  type        = number
  default     = 1000

  validation {
    condition     = var.waf_rate_limit >= 10
    error_message = "waf_rate_limit must be at least 10 (WAF minimum)."
  }
}

variable "instance_type" {
  description = "EC2 instance type for the app tier."
  type        = string
  default     = "t3.micro"
}

variable "root_volume_size" {
  description = "Root EBS volume size (GiB)."
  type        = number
  default     = 8

  validation {
    condition     = var.root_volume_size >= 8 && var.root_volume_size <= 50
    error_message = "root_volume_size must be between 8 and 50 GiB."
  }
}

variable "ami_ssm_parameter" {
  description = "Public SSM parameter resolving the AMI (Amazon Linux 2023 includes the SSM agent)."
  type        = string
  default     = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

variable "asg_min_size" {
  description = "Minimum app instances."
  type        = number
  default     = 2
}

variable "asg_desired_capacity" {
  description = "Desired app instances (one per AZ by default)."
  type        = number
  default     = 2
}

variable "asg_max_size" {
  description = "Maximum app instances."
  type        = number
  default     = 4

  validation {
    condition     = var.asg_max_size <= 10
    error_message = "asg_max_size is capped at 10 for a lab."
  }
}

# ---------------------------------------------------------------------------
# Logging and detection
# ---------------------------------------------------------------------------

variable "log_retention_days" {
  description = "CloudWatch Logs retention for every log group in this profile."
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.log_retention_days)
    error_message = "log_retention_days must be a value accepted by CloudWatch Logs."
  }
}

variable "flow_logs_aggregation_interval" {
  description = "Flow log aggregation window in seconds (60 or 600)."
  type        = number
  default     = 60

  validation {
    condition     = contains([60, 600], var.flow_logs_aggregation_interval)
    error_message = "flow_logs_aggregation_interval must be 60 or 600."
  }
}

variable "s3_log_expiration_days" {
  description = "Days before flow log and ALB log objects are deleted from S3."
  type        = number
  default     = 90

  validation {
    condition     = var.s3_log_expiration_days >= 1
    error_message = "s3_log_expiration_days must be at least 1."
  }
}

variable "s3_force_destroy" {
  description = "Let terraform destroy empty and delete the log buckets (keep true for a lab)."
  type        = bool
  default     = true
}

variable "athena_bytes_scanned_cutoff" {
  description = "Per-query Athena scan limit in bytes (cost guard). Minimum 10 MB."
  type        = number
  default     = 1073741824

  validation {
    condition     = var.athena_bytes_scanned_cutoff >= 10485760
    error_message = "athena_bytes_scanned_cutoff must be at least 10485760 (10 MB)."
  }
}

variable "alert_email" {
  description = "Email subscribed to the security alarm SNS topic (confirm the subscription email). Null = topic only."
  type        = string
  default     = null
}

variable "rejected_flows_threshold" {
  description = "Rejected flow records per 5 minutes that trigger the alarm."
  type        = number
  default     = 500
}

# ---------------------------------------------------------------------------
# Cost guardrail
# ---------------------------------------------------------------------------

variable "budget_alert_email" {
  description = "If set, creates an AWS Budget that emails at 80% actual / 100% forecast of monthly_budget_usd."
  type        = string
  default     = null
}

variable "monthly_budget_usd" {
  description = "Monthly cost budget (USD) used when budget_alert_email is set."
  type        = number
  default     = 800
}
