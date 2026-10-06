data "aws_availability_zones" "available" {
  #checkov:skip=CKV_AWS_394:Only names[0] is used, and availability_zone can pin an explicit AZ.
  state = "available"
}

data "aws_caller_identity" "current" {}

data "aws_region" "current" {}

data "aws_partition" "current" {}

data "aws_ssm_parameter" "ami" {
  name = var.ami_ssm_parameter
}

locals {
  name              = "${var.project_name}-${var.environment}"
  availability_zone = coalesce(var.availability_zone, data.aws_availability_zones.available.names[0])
}

module "network" {
  source = "./modules/network"

  name                = local.name
  vpc_cidr            = var.vpc_cidr
  public_subnet_cidr  = var.public_subnet_cidr
  private_subnet_cidr = var.private_subnet_cidr
  availability_zone   = local.availability_zone
  admin_cidrs         = var.admin_cidrs
}

module "security" {
  source = "./modules/security"

  name        = local.name
  vpc_id      = module.network.vpc_id
  admin_cidrs = var.admin_cidrs
}

module "compute" {
  source = "./modules/compute"

  name              = local.name
  ami_id            = nonsensitive(data.aws_ssm_parameter.ami.value)
  instance_type     = var.instance_type
  root_volume_size  = var.root_volume_size
  public_subnet_id  = module.network.public_subnet_id
  private_subnet_id = module.network.private_subnet_id
  bastion_sg_id     = module.security.bastion_sg_id
  web_sg_id         = module.security.web_sg_id
  ssh_public_key    = trimspace(var.ssh_public_key)

  # The web server installs httpd from the internet at first boot, so the NAT
  # route and the security-group egress rules must exist before it launches.
  depends_on = [module.network, module.security]
}

module "flow_logs" {
  source = "./modules/flow_logs"

  name                     = local.name
  vpc_id                   = module.network.vpc_id
  traffic_type             = var.flow_logs_traffic_type
  retention_in_days        = var.flow_logs_retention_days
  max_aggregation_interval = var.flow_logs_aggregation_interval
  enable_kms               = var.enable_kms_encryption
  enable_s3_archive        = var.enable_s3_flow_log_archive
  s3_expiration_days       = var.s3_archive_expiration_days
  s3_force_destroy         = var.s3_archive_force_destroy
  account_id               = data.aws_caller_identity.current.account_id
  region                   = data.aws_region.current.name
  partition                = data.aws_partition.current.partition
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
