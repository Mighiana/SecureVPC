# SecureVPC advanced profile (2026 extension). Not part of the 2025 console
# build; see README "Advanced profile". Request path:
#
#   client -> IGW -> Network Firewall -> ALB + WAF -> app ASG (private)
#   app -> VPC endpoints (SSM, Logs, KMS, S3)      -- no internet needed
#   app -> NAT -> Network Firewall -> IGW          -- only allowlisted domains
#   every DNS query -> Route 53 Resolver DNS Firewall

data "aws_availability_zones" "available" {
  #checkov:skip=CKV_AWS_394:Only the first az_count names are used, and availability_zones can pin explicit AZs.
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter
}

locals {
  name      = "${var.project_name}-${var.environment}"
  azs       = length(var.availability_zones) > 0 ? var.availability_zones : slice(data.aws_availability_zones.available.names, 0, var.az_count)
  account   = data.aws_caller_identity.current.account_id
  region    = data.aws_region.current.name
  partition = data.aws_partition.current.partition

  internet_egress = length(var.egress_allowed_domains) > 0

  log_groups = {
    firewall_alert = "/${local.name}/network-firewall/alert"
    firewall_flow  = "/${local.name}/network-firewall/flow"
    dns_queries    = "/${local.name}/route53-resolver/queries"
    ssm_sessions   = "/${local.name}/ssm/sessions"
    waf            = "aws-waf-logs-${local.name}"
  }

  # AWS service and VPC-internal names must always resolve (endpoint private
  # DNS, S3 package repos, instance hostnames).
  dns_allowed_domains = concat(
    ["amazonaws.com", "ec2.internal", "compute.internal"],
    var.egress_allowed_domains,
  )

  interface_endpoints = ["ssm", "ssmmessages", "ec2messages", "logs", "kms"]

  # Version 5 fields: who (pkt-src/dst behind NAT), where (subnet/AZ),
  # which way (flow-direction) and which path (traffic-path, AWS service).
  flow_log_fields = [
    "version", "account-id", "interface-id", "srcaddr", "dstaddr", "srcport", "dstport",
    "protocol", "packets", "bytes", "start", "end", "action", "log-status",
    "vpc-id", "subnet-id", "instance-id", "tcp-flags", "type", "pkt-srcaddr", "pkt-dstaddr",
    "region", "az-id", "flow-direction", "traffic-path", "pkt-src-aws-service", "pkt-dst-aws-service",
  ]
}

module "network" {
  source = "../modules/tiered_network"

  name                    = local.name
  vpc_cidr                = var.vpc_cidr
  azs                     = local.azs
  enable_nat_gateway      = local.internet_egress
  single_nat_gateway      = var.single_nat_gateway
  enable_firewall_subnets = var.enable_network_firewall
  data_port               = var.data_port
}

module "firewall" {
  source = "../modules/network_firewall"
  count  = var.enable_network_firewall ? 1 : 0

  name                    = local.name
  vpc_id                  = module.network.vpc_id
  vpc_cidr                = module.network.vpc_cidr
  firewall_subnet_ids     = module.network.subnet_ids.firewall
  firewall_route_table_id = module.network.firewall_route_table_id
  public_route_table_ids  = module.network.public_route_table_ids
  public_subnet_cidrs     = module.network.subnet_cidrs.public
  igw_id                  = module.network.igw_id
  egress_allowed_domains  = var.egress_allowed_domains
  managed_rule_groups     = var.network_firewall_managed_rule_groups
  kms_key_arn             = aws_kms_key.this.arn
  alert_log_group_name    = local.log_groups.firewall_alert
  flow_log_group_name     = local.log_groups.firewall_flow
  log_retention_days      = var.log_retention_days
  delete_protection       = var.firewall_delete_protection
  region                  = local.region
  partition               = local.partition

  depends_on = [aws_cloudwatch_log_resource_policy.vended_logs]
}

module "security" {
  source = "../modules/tier_security"

  name                  = local.name
  vpc_id                = module.network.vpc_id
  region                = local.region
  alb_ingress_cidrs     = var.alb_ingress_cidrs
  enable_https          = var.certificate_arn != null
  allow_internet_egress = local.internet_egress
  data_port             = var.data_port
}

module "endpoints" {
  source = "../modules/vpc_endpoints"

  name               = local.name
  vpc_id             = module.network.vpc_id
  region             = local.region
  partition          = local.partition
  account_id         = local.account
  subnet_ids         = values(module.network.subnet_ids.endpoints)
  security_group_id  = module.security.endpoints_sg_id
  interface_services = local.interface_endpoints
  gateway_route_table_ids = concat(
    values(module.network.app_route_table_ids),
    [module.network.isolated_route_table_ids.data],
  )
}

module "dns_firewall" {
  source = "../modules/dns_firewall"
  count  = var.enable_dns_firewall ? 1 : 0

  name                    = local.name
  vpc_id                  = module.network.vpc_id
  allowed_domains         = local.dns_allowed_domains
  managed_domain_list_ids = var.dns_firewall_managed_domain_list_ids
  block_unlisted          = var.dns_firewall_block_unlisted
  fail_open               = var.dns_firewall_fail_open
  query_log_group_name    = local.log_groups.dns_queries
  kms_key_arn             = aws_kms_key.this.arn
  log_retention_days      = var.log_retention_days

  depends_on = [aws_cloudwatch_log_resource_policy.vended_logs]
}

module "web" {
  source = "../modules/web_tier"

  name                     = local.name
  vpc_id                   = module.network.vpc_id
  region                   = local.region
  partition                = local.partition
  account_id               = local.account
  ami_id                   = nonsensitive(data.aws_ssm_parameter.ami.value)
  instance_type            = var.instance_type
  root_volume_size         = var.root_volume_size
  public_subnet_ids        = values(module.network.subnet_ids.public)
  app_subnet_ids           = values(module.network.subnet_ids.app)
  alb_sg_id                = module.security.alb_sg_id
  app_sg_id                = module.security.app_sg_id
  asg_min_size             = var.asg_min_size
  asg_desired_capacity     = var.asg_desired_capacity
  asg_max_size             = var.asg_max_size
  certificate_arn          = var.certificate_arn
  web_hostname             = var.web_hostname
  waf_rate_limit           = var.waf_rate_limit
  waf_log_group_name       = local.log_groups.waf
  session_log_group_name   = local.log_groups.ssm_sessions
  kms_key_arn              = aws_kms_key.this.arn
  log_retention_days       = var.log_retention_days
  alb_logs_expiration_days = var.s3_log_expiration_days
  force_destroy            = var.s3_force_destroy
  deletion_protection      = false

  # Instances install httpd from S3 and register with SSM at first boot, so
  # the endpoints, routes (incl. firewall) and SG rules must exist first.
  depends_on = [module.network, module.security, module.endpoints, module.firewall, module.dns_firewall]
}

module "flow_logs" {
  source = "../modules/flow_logs"

  name                          = local.name
  vpc_id                        = module.network.vpc_id
  traffic_type                  = "ALL"
  retention_in_days             = var.log_retention_days
  max_aggregation_interval      = var.flow_logs_aggregation_interval
  enable_kms                    = true
  enable_s3_archive             = true
  s3_expiration_days            = var.s3_log_expiration_days
  s3_force_destroy              = var.s3_force_destroy
  s3_log_format                 = join(" ", [for f in local.flow_log_fields : "$${${f}}"])
  s3_hive_compatible_partitions = true
  account_id                    = local.account
  region                        = local.region
  partition                     = local.partition
}

module "analytics" {
  source = "../modules/flow_log_analytics"

  name                 = local.name
  bucket_name          = module.flow_logs.s3_bucket_name
  account_id           = local.account
  region               = local.region
  fields               = local.flow_log_fields
  kms_key_arn          = module.flow_logs.kms_key_arn
  bytes_scanned_cutoff = var.athena_bytes_scanned_cutoff
}

resource "aws_budgets_budget" "monthly" {
  count = var.budget_alert_email == null ? 0 : 1

  name         = "${local.name}-monthly"
  budget_type  = "COST"
  limit_amount = tostring(var.monthly_budget_usd)
  limit_unit   = "USD"
  time_unit    = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = [var.budget_alert_email]
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "FORECASTED"
    subscriber_email_addresses = [var.budget_alert_email]
  }
}
