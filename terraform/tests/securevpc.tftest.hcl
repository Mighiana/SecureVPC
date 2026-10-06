# Offline tests: the AWS provider is mocked, so no credentials are needed and
# nothing is created. Run with `terraform test` from the terraform/ directory.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b"]
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_region" {
    defaults = {
      name = "us-east-1"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }

  mock_data "aws_ssm_parameter" {
    defaults = {
      value = "ami-0123456789abcdef0"
    }
  }

  # Resources whose ARNs are validated by other resources need realistic mocks.
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/securevpc-lab/vpc-flow-logs"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/securevpc-lab-flowlogs-mock"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::securevpc-lab-flow-logs-mock"
    }
  }
}

variables {
  admin_cidrs    = ["203.0.113.10/32"]
  ssh_public_key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestOnlyNotARealKeyForTerraformTests00 test"
}

# ---------------------------------------------------------------------------
# Full stack wiring
# ---------------------------------------------------------------------------

run "full_stack_applies_with_defaults" {
  command = apply

  assert {
    condition     = output.vpc_cidr == "10.0.0.0/16"
    error_message = "Default VPC CIDR should be 10.0.0.0/16."
  }

  assert {
    condition     = output.availability_zone == "us-east-1a"
    error_message = "Should default to the first available AZ."
  }

  assert {
    condition     = output.flow_logs_s3_bucket == null
    error_message = "S3 archive must be off by default."
  }

  assert {
    condition     = output.flow_logs_kms_key_arn != null
    error_message = "KMS encryption for flow logs should be on by default."
  }

  assert {
    condition     = length(output.logs_insights_queries) == 3
    error_message = "Expected three saved Logs Insights queries."
  }
}

# ---------------------------------------------------------------------------
# Input guardrails
# ---------------------------------------------------------------------------

run "rejects_ssh_open_to_world" {
  command = plan

  variables {
    admin_cidrs = ["0.0.0.0/0"]
  }

  expect_failures = [var.admin_cidrs]
}

run "rejects_overly_wide_admin_cidr" {
  command = plan

  variables {
    admin_cidrs = ["10.0.0.0/8"]
  }

  expect_failures = [var.admin_cidrs]
}

run "rejects_invalid_cidr" {
  command = plan

  variables {
    admin_cidrs = ["not-a-cidr"]
  }

  expect_failures = [var.admin_cidrs]
}

run "rejects_private_key_material" {
  command = plan

  variables {
    ssh_public_key = "-----BEGIN OPENSSH PRIVATE KEY-----"
  }

  expect_failures = [var.ssh_public_key]
}

# ---------------------------------------------------------------------------
# Network module
# ---------------------------------------------------------------------------

run "network_segmentation" {
  command = apply

  module {
    source = "./modules/network"
  }

  variables {
    name                = "t"
    vpc_cidr            = "10.0.0.0/16"
    public_subnet_cidr  = "10.0.1.0/24"
    private_subnet_cidr = "10.0.2.0/24"
    availability_zone   = "us-east-1a"
    admin_cidrs         = ["203.0.113.10/32", "198.51.100.0/24"]
  }

  assert {
    condition     = !aws_subnet.public.map_public_ip_on_launch && !aws_subnet.private.map_public_ip_on_launch
    error_message = "No subnet may auto-assign public IPs."
  }

  assert {
    condition     = aws_route.public_internet.gateway_id == aws_internet_gateway.this.id
    error_message = "Public subnet default route must target the Internet Gateway."
  }

  assert {
    condition     = aws_route.private_nat.nat_gateway_id == aws_nat_gateway.this.id
    error_message = "Private subnet default route must target the NAT Gateway."
  }

  assert {
    condition     = aws_nat_gateway.this.subnet_id == aws_subnet.public.id
    error_message = "NAT Gateway must live in the public subnet."
  }

  assert {
    condition     = length(aws_default_security_group.this.ingress) == 0 && length(aws_default_security_group.this.egress) == 0
    error_message = "Default security group must have no rules."
  }

  assert {
    condition     = toset([for r in aws_network_acl_rule.public_in_ssh_admin : r.cidr_block]) == toset(["203.0.113.10/32", "198.51.100.0/24"])
    error_message = "Public NACL SSH must be limited to admin CIDRs."
  }

  assert {
    condition = alltrue([for r in [
      aws_network_acl_rule.private_in_ssh_from_public,
      aws_network_acl_rule.private_in_http_from_public,
    ] : r.cidr_block == "10.0.1.0/24"])
    error_message = "Private NACL must only accept SSH/HTTP from the public subnet."
  }

  assert {
    condition     = aws_network_acl_rule.private_out_ephemeral_to_public.cidr_block == "10.0.1.0/24"
    error_message = "Private NACL return traffic must only go to the public subnet."
  }
}

# ---------------------------------------------------------------------------
# Security module
# ---------------------------------------------------------------------------

run "security_groups_chain_bastion_to_web" {
  command = apply

  module {
    source = "./modules/security"
  }

  variables {
    name        = "t"
    vpc_id      = "vpc-12345678"
    admin_cidrs = ["203.0.113.10/32"]
  }

  assert {
    condition     = [for r in aws_vpc_security_group_ingress_rule.bastion_ssh_admin : r.cidr_ipv4] == ["203.0.113.10/32"]
    error_message = "Bastion SSH ingress must be limited to admin CIDRs."
  }

  assert {
    condition = alltrue([for r in [
      aws_vpc_security_group_ingress_rule.web_ssh_from_bastion,
      aws_vpc_security_group_ingress_rule.web_http_from_bastion,
    ] : r.referenced_security_group_id == aws_security_group.bastion.id && r.cidr_ipv4 == null])
    error_message = "Web server ingress must reference the bastion SG, never a CIDR."
  }
}

# ---------------------------------------------------------------------------
# Compute module
# ---------------------------------------------------------------------------

run "instances_hardened" {
  command = apply

  module {
    source = "./modules/compute"
  }

  variables {
    name              = "t"
    ami_id            = "ami-0123456789abcdef0"
    instance_type     = "t3.micro"
    public_subnet_id  = "subnet-public"
    private_subnet_id = "subnet-private"
    bastion_sg_id     = "sg-bastion"
    web_sg_id         = "sg-web"
    root_volume_size  = 8
    ssh_public_key    = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAITestOnlyNotARealKeyForTerraformTests00 test"
  }

  assert {
    condition     = aws_instance.web.associate_public_ip_address == false
    error_message = "Web server must not get a public IP."
  }

  assert {
    condition     = aws_instance.web.subnet_id == "subnet-private" && aws_instance.bastion.subnet_id == "subnet-public"
    error_message = "Instances must be placed in their intended tiers."
  }

  assert {
    condition     = aws_instance.web.metadata_options[0].http_tokens == "required" && aws_instance.bastion.metadata_options[0].http_tokens == "required"
    error_message = "IMDSv2 must be required on both instances."
  }

  assert {
    condition     = aws_instance.web.root_block_device[0].encrypted && aws_instance.bastion.root_block_device[0].encrypted
    error_message = "Root volumes must be encrypted."
  }
}

# ---------------------------------------------------------------------------
# Flow logs module
# ---------------------------------------------------------------------------

run "flow_logs_with_s3_archive" {
  command = apply

  module {
    source = "./modules/flow_logs"
  }

  variables {
    name                     = "t"
    vpc_id                   = "vpc-12345678"
    traffic_type             = "ALL"
    retention_in_days        = 14
    max_aggregation_interval = 60
    enable_kms               = true
    enable_s3_archive        = true
    s3_expiration_days       = 30
    s3_force_destroy         = true
    account_id               = "123456789012"
    region                   = "us-east-1"
    partition                = "aws"
  }

  assert {
    condition     = aws_flow_log.cloudwatch.traffic_type == "ALL" && aws_flow_log.cloudwatch.log_destination_type == "cloud-watch-logs"
    error_message = "Flow log must capture ALL traffic into CloudWatch Logs."
  }

  assert {
    condition     = aws_cloudwatch_log_group.flow_logs.retention_in_days == 14
    error_message = "Log group retention must be set (never infinite)."
  }

  assert {
    condition     = aws_kms_key.logs[0].enable_key_rotation
    error_message = "KMS key rotation must be enabled."
  }

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.archive[0].block_public_acls,
      aws_s3_bucket_public_access_block.archive[0].block_public_policy,
      aws_s3_bucket_public_access_block.archive[0].ignore_public_acls,
      aws_s3_bucket_public_access_block.archive[0].restrict_public_buckets,
    ])
    error_message = "Archive bucket must block all public access."
  }

  assert {
    condition     = aws_flow_log.s3[0].log_destination_type == "s3"
    error_message = "Second flow log must deliver to S3 when the archive is enabled."
  }
}
