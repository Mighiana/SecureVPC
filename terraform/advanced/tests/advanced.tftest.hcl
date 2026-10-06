# Offline tests for the advanced profile: the AWS provider is mocked, so no
# credentials are needed and nothing is created. Run `terraform test` from
# terraform/advanced/.

mock_provider "aws" {
  mock_data "aws_availability_zones" {
    defaults = {
      names = ["us-east-1a", "us-east-1b", "us-east-1c"]
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

  mock_data "aws_ec2_managed_prefix_list" {
    defaults = {
      id = "pl-63a5400a"
    }
  }

  mock_data "aws_elb_service_account" {
    defaults = {
      arn = "arn:aws:iam::127311923021:root"
    }
  }

  mock_data "aws_default_tags" {
    defaults = {
      tags = { Project = "SecureVPC" }
    }
  }

  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }

  # Resources whose ARNs are validated by other resources need realistic mocks.
  mock_resource "aws_cloudwatch_log_group" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:log-group:/securevpc-adv/mock"
    }
  }

  mock_resource "aws_iam_role" {
    defaults = {
      arn = "arn:aws:iam::123456789012:role/securevpc-adv-mock"
    }
  }

  mock_resource "aws_iam_instance_profile" {
    defaults = {
      arn = "arn:aws:iam::123456789012:instance-profile/securevpc-adv-mock"
    }
  }

  mock_resource "aws_kms_key" {
    defaults = {
      arn = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    }
  }

  mock_resource "aws_s3_bucket" {
    defaults = {
      arn    = "arn:aws:s3:::securevpc-adv-mock"
      bucket = "securevpc-adv-mock"
    }
  }

  mock_resource "aws_sns_topic" {
    defaults = {
      arn = "arn:aws:sns:us-east-1:123456789012:securevpc-adv-security-alerts"
    }
  }

  mock_resource "aws_networkfirewall_rule_group" {
    defaults = {
      arn = "arn:aws:network-firewall:us-east-1:123456789012:stateful-rulegroup/securevpc-adv-segmentation"
    }
  }

  mock_resource "aws_networkfirewall_firewall_policy" {
    defaults = {
      arn = "arn:aws:network-firewall:us-east-1:123456789012:firewall-policy/securevpc-adv-policy"
    }
  }

  mock_resource "aws_networkfirewall_firewall" {
    defaults = {
      arn = "arn:aws:network-firewall:us-east-1:123456789012:firewall/securevpc-adv-fw"
      firewall_status = [{
        sync_states = [
          { availability_zone = "us-east-1a", attachment = [{ endpoint_id = "vpce-0fwaaaaaaaaaaaaaa", subnet_id = "subnet-fwa", status = "READY" }] },
          { availability_zone = "us-east-1b", attachment = [{ endpoint_id = "vpce-0fwbbbbbbbbbbbbbb", subnet_id = "subnet-fwb", status = "READY" }] },
        ]
      }]
    }
  }

  mock_resource "aws_launch_template" {
    defaults = {
      id             = "lt-0123456789abcdef0"
      latest_version = 1
    }
  }

  mock_resource "aws_lb" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:loadbalancer/app/securevpc-adv-alb/0123456789abcdef"
      arn_suffix = "app/securevpc-adv-alb/0123456789abcdef"
      dns_name   = "securevpc-adv-alb-123.us-east-1.elb.amazonaws.com"
    }
  }

  mock_resource "aws_lb_target_group" {
    defaults = {
      arn        = "arn:aws:elasticloadbalancing:us-east-1:123456789012:targetgroup/securevpc-adv-app-tg/0123456789abcdef"
      arn_suffix = "targetgroup/securevpc-adv-app-tg/0123456789abcdef"
    }
  }

  mock_resource "aws_wafv2_web_acl" {
    defaults = {
      arn = "arn:aws:wafv2:us-east-1:123456789012:regional/webacl/securevpc-adv-web-acl/00000000-0000-0000-0000-000000000000"
    }
  }

  mock_resource "aws_ssm_document" {
    defaults = {
      arn = "arn:aws:ssm:us-east-1:123456789012:document/securevpc-adv-session-preferences"
    }
  }
}

# ---------------------------------------------------------------------------
# Root profile
# ---------------------------------------------------------------------------

run "full_stack_applies_with_defaults" {
  command = apply

  assert {
    condition     = output.availability_zones == tolist(["us-east-1a", "us-east-1b"])
    error_message = "Defaults should spread across the first two AZs."
  }

  assert {
    condition     = alltrue([for tier in ["firewall", "public", "app", "endpoints", "data"] : length(output.subnet_ids[tier]) == 2])
    error_message = "Every tier needs one subnet per AZ."
  }

  assert {
    condition     = length(output.nat_public_ips) == 0
    error_message = "No NAT Gateway (and no internet egress) when egress_allowed_domains is empty."
  }

  assert {
    condition     = output.network_firewall != null && length(output.network_firewall.endpoint_ids) == 2
    error_message = "Network Firewall should be on by default with one endpoint per AZ."
  }

  assert {
    condition     = toset(keys(output.vpc_endpoints.interface)) == toset(["ssm", "ssmmessages", "ec2messages", "logs", "kms"])
    error_message = "Session Manager needs the ssm, ssmmessages and ec2messages endpoints (plus logs and kms)."
  }

  assert {
    condition     = length(output.alarm_names) == 5
    error_message = "Expected alarms for rejected flows, WAF, unhealthy targets, firewall drops and DNS blocks."
  }

  assert {
    condition     = alltrue([for k, v in output.log_groups : v != null])
    error_message = "Every log group should exist with the default toggles."
  }

  assert {
    condition     = output.flow_log_archive.bucket != null && length(output.flow_log_archive.named_queries) == 3
    error_message = "Flow logs must be archived to S3 with saved Athena queries."
  }

  assert {
    condition     = startswith(output.web_url, "http://")
    error_message = "Without a certificate the web tier is HTTP."
  }

  assert {
    condition     = strcontains(output.start_session_command, "--document-name securevpc-adv-session-preferences")
    error_message = "The session command must use the logged session document."
  }
}

run "allowlisted_egress_creates_nat" {
  command = apply

  variables {
    egress_allowed_domains = ["github.com", ".pypi.org."]
  }

  assert {
    condition     = length(output.nat_public_ips) == 1
    error_message = "single_nat_gateway should create exactly one NAT Gateway when egress is allowed."
  }
}

run "cheap_mode_without_firewalls" {
  command = apply

  variables {
    enable_network_firewall = false
    enable_dns_firewall     = false
  }

  assert {
    condition     = output.network_firewall == null && length(output.subnet_ids.firewall) == 0
    error_message = "Disabling the firewall must drop its subnets too."
  }

  assert {
    condition     = length(output.alarm_names) == 3
    error_message = "Firewall and DNS alarms must disappear with their features."
  }
}

run "rejects_egress_allowlist_without_firewall" {
  command = plan

  variables {
    enable_network_firewall = false
    egress_allowed_domains  = ["github.com"]
  }

  expect_failures = [var.egress_allowed_domains]
}

run "rejects_certificate_without_hostname" {
  command = plan

  variables {
    certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
  }

  expect_failures = [var.web_hostname]
}

run "rejects_invalid_web_hostname" {
  command = plan

  variables {
    certificate_arn = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
    web_hostname    = "-demo.example.com"
  }

  expect_failures = [var.web_hostname]
}

run "rejects_wildcard_or_url_egress" {
  command = plan

  variables {
    egress_allowed_domains = ["*.example.com", "https://example.com/x"]
  }

  expect_failures = [var.egress_allowed_domains]
}

run "rejects_non_strict_order_managed_groups" {
  command = plan

  variables {
    network_firewall_managed_rule_groups = ["MalwareDomainsActionOrder"]
  }

  expect_failures = [var.network_firewall_managed_rule_groups]
}

run "rejects_ssh_as_data_port" {
  command = plan

  variables {
    data_port = 22
  }

  expect_failures = [var.data_port]
}

run "rejects_bad_dns_list_id" {
  command = plan

  variables {
    dns_firewall_managed_domain_list_ids = ["AWSManagedDomainsMalwareDomainList"]
  }

  expect_failures = [var.dns_firewall_managed_domain_list_ids]
}

# ---------------------------------------------------------------------------
# Tiered network
# ---------------------------------------------------------------------------

run "network_tiers_and_routes" {
  command = apply

  module {
    source = "../modules/tiered_network"
  }

  variables {
    name                    = "t"
    vpc_cidr                = "10.0.0.0/16"
    azs                     = ["us-east-1a", "us-east-1b"]
    enable_nat_gateway      = true
    single_nat_gateway      = false
    enable_firewall_subnets = true
    data_port               = 5432
  }

  assert {
    condition = alltrue(concat(
      [for s in aws_subnet.public : !s.map_public_ip_on_launch],
      [for s in aws_subnet.app : !s.map_public_ip_on_launch],
      [for s in aws_subnet.endpoint : !s.map_public_ip_on_launch],
      [for s in aws_subnet.data : !s.map_public_ip_on_launch],
    ))
    error_message = "No subnet may auto-assign public IPs."
  }

  assert {
    condition     = aws_subnet.firewall["us-east-1a"].cidr_block == "10.0.0.0/28" && aws_subnet.data["us-east-1b"].cidr_block == "10.0.32.0/24"
    error_message = "Tier CIDR plan changed unexpectedly."
  }

  assert {
    condition     = length(aws_route.public_internet) == 0
    error_message = "With the firewall, public subnets must not route straight to the IGW."
  }

  assert {
    condition     = alltrue([for az, r in aws_route.app_nat : r.nat_gateway_id == aws_nat_gateway.this[az].id])
    error_message = "With one NAT per AZ, each app subnet must use its own AZ's NAT Gateway."
  }

  assert {
    condition     = alltrue([for az, n in aws_nat_gateway.this : n.subnet_id == aws_subnet.public[az].id])
    error_message = "NAT Gateways must live in the public tier."
  }

  assert {
    condition     = length(aws_default_security_group.this.ingress) == 0 && length(aws_default_security_group.this.egress) == 0
    error_message = "Default security group must have no rules."
  }

  assert {
    condition     = toset([for r in aws_network_acl_rule.app_in_http_from_public : r.cidr_block]) == toset(["10.0.1.0/24", "10.0.2.0/24"]) && alltrue([for r in aws_network_acl_rule.app_in_http_from_public : r.from_port == 80 && r.to_port == 80])
    error_message = "App tier may only accept HTTP from the public (ALB) subnets."
  }

  assert {
    condition     = toset([for r in aws_network_acl_rule.data_in_from_app : r.cidr_block]) == toset(["10.0.11.0/24", "10.0.12.0/24"]) && alltrue([for r in aws_network_acl_rule.data_in_from_app : r.from_port == 5432 && r.to_port == 5432])
    error_message = "Data tier may only accept the data port from the app subnets."
  }

  assert {
    condition     = toset([for r in aws_network_acl_rule.endpoint_in_https_from_app : r.cidr_block]) == toset(["10.0.11.0/24", "10.0.12.0/24"])
    error_message = "Endpoint tier may only accept HTTPS from the app subnets."
  }

  assert {
    condition = alltrue([for r in concat(
      values(aws_network_acl_rule.public_in),
      aws_network_acl_rule.app_in_http_from_public,
      aws_network_acl_rule.data_in_from_app,
      aws_network_acl_rule.endpoint_in_https_from_app,
    ) : !(r.from_port <= 22 && r.to_port >= 22)])
    error_message = "No NACL may admit SSH (TCP/22) into any tier."
  }
}

run "network_without_nat_has_no_default_route" {
  command = apply

  module {
    source = "../modules/tiered_network"
  }

  variables {
    name                    = "t"
    vpc_cidr                = "10.0.0.0/16"
    azs                     = ["us-east-1a", "us-east-1b"]
    enable_nat_gateway      = false
    single_nat_gateway      = true
    enable_firewall_subnets = false
    data_port               = 5432
  }

  assert {
    condition     = length(aws_nat_gateway.this) == 0 && length(aws_route.app_nat) == 0
    error_message = "Without allowlisted egress the app tier must have no route to the internet."
  }

  assert {
    condition     = alltrue([for r in aws_route.public_internet : r.gateway_id == aws_internet_gateway.this.id]) && length(aws_route.public_internet) == 2
    error_message = "Without the firewall, public subnets route to the IGW."
  }
}

# ---------------------------------------------------------------------------
# Network Firewall
# ---------------------------------------------------------------------------

run "firewall_inspects_both_directions" {
  command = apply

  module {
    source = "../modules/network_firewall"
  }

  variables {
    name                    = "t"
    vpc_id                  = "vpc-12345678"
    vpc_cidr                = "10.0.0.0/16"
    firewall_subnet_ids     = { "us-east-1a" = "subnet-fwa", "us-east-1b" = "subnet-fwb" }
    firewall_route_table_id = "rtb-firewall"
    public_route_table_ids  = { "us-east-1a" = "rtb-puba", "us-east-1b" = "rtb-pubb" }
    public_subnet_cidrs     = { "us-east-1a" = "10.0.1.0/24", "us-east-1b" = "10.0.2.0/24" }
    igw_id                  = "igw-12345678"
    egress_allowed_domains  = ["GitHub.com.", ".pypi.org"]
    managed_rule_groups     = ["MalwareDomainsStrictOrder", "ThreatSignaturesBotnetStrictOrder"]
    kms_key_arn             = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    alert_log_group_name    = "/t/network-firewall/alert"
    flow_log_group_name     = "/t/network-firewall/flow"
    log_retention_days      = 30
    delete_protection       = false
    region                  = "us-east-1"
    partition               = "aws"
  }

  assert {
    condition     = aws_route.public_via_firewall["us-east-1a"].vpc_endpoint_id == "vpce-0fwaaaaaaaaaaaaaa" && aws_route.public_via_firewall["us-east-1b"].vpc_endpoint_id == "vpce-0fwbbbbbbbbbbbbbb"
    error_message = "Each public subnet's default route must go to its own AZ's firewall endpoint (symmetric routing)."
  }

  assert {
    condition     = aws_route.igw_edge_to_firewall["us-east-1a"].destination_cidr_block == "10.0.1.0/24" && aws_route.igw_edge_to_firewall["us-east-1a"].vpc_endpoint_id == "vpce-0fwaaaaaaaaaaaaaa"
    error_message = "IGW edge route table must send inbound traffic through the same-AZ firewall endpoint."
  }

  assert {
    condition     = aws_route_table_association.igw_edge.gateway_id == "igw-12345678"
    error_message = "Edge route table must be associated with the Internet Gateway."
  }

  assert {
    condition     = aws_route.firewall_to_igw.gateway_id == "igw-12345678"
    error_message = "Firewall subnets must route to the IGW."
  }

  assert {
    condition     = aws_networkfirewall_firewall_policy.this.firewall_policy[0].stateful_default_actions == toset(["aws:drop_established", "aws:alert_established"])
    error_message = "Default action must drop (and log) anything not explicitly passed."
  }

  assert {
    condition     = aws_networkfirewall_firewall_policy.this.firewall_policy[0].stateful_engine_options[0].rule_order == "STRICT_ORDER"
    error_message = "Policy must use strict rule ordering."
  }

  assert {
    condition     = contains([for r in aws_networkfirewall_firewall_policy.this.firewall_policy[0].stateful_rule_group_reference : r.resource_arn], "arn:aws:network-firewall:us-east-1:aws-managed:stateful-rulegroup/ThreatSignaturesBotnetStrictOrder")
    error_message = "Managed threat groups must be referenced by their AWS-managed ARN."
  }

  assert {
    condition     = alltrue([for r in aws_networkfirewall_firewall_policy.this.firewall_policy[0].stateful_rule_group_reference : r.priority < 1000 if strcontains(r.resource_arn, "aws-managed")])
    error_message = "Managed threat groups must be evaluated before the custom allow rules."
  }

  assert {
    condition     = strcontains(output.rules[3], "content:\".github.com\"") && strcontains(output.rules[5], "content:\".pypi.org\"")
    error_message = "Allowlisted domains must be normalised (lowercase, no leading/trailing dot)."
  }

  assert {
    condition     = startswith(output.rules[length(output.rules) - 1], "drop tcp $EXTERNAL_NET any -> $HOME_NET any") && length([for r in output.rules : r if startswith(r, "drop ")]) == 6
    error_message = "Custom rules must end with explicit drops, including inbound traffic not aimed at the ALB."
  }

  assert {
    condition     = length(distinct([for r in output.rules : regex("sid:([0-9]+);", r)[0]])) == length(output.rules)
    error_message = "Every Suricata rule needs a unique sid."
  }

  assert {
    condition     = length(aws_networkfirewall_logging_configuration.this.logging_configuration[0].log_destination_config) == 2
    error_message = "Both ALERT and FLOW logs must be delivered."
  }
}

# ---------------------------------------------------------------------------
# Security groups
# ---------------------------------------------------------------------------

run "security_groups_have_no_ssh_and_chain_by_role" {
  command = apply

  module {
    source = "../modules/tier_security"
  }

  variables {
    name                  = "t"
    vpc_id                = "vpc-12345678"
    region                = "us-east-1"
    alb_ingress_cidrs     = ["203.0.113.10/32"]
    enable_https          = false
    allow_internet_egress = false
    data_port             = 5432
  }

  assert {
    condition = alltrue([for r in concat(
      values(aws_vpc_security_group_ingress_rule.alb_http),
      values(aws_vpc_security_group_ingress_rule.alb_https),
      [aws_vpc_security_group_ingress_rule.app_from_alb, aws_vpc_security_group_ingress_rule.endpoints_from_app, aws_vpc_security_group_ingress_rule.data_from_app],
    ) : !(r.from_port <= 22 && r.to_port >= 22)])
    error_message = "No security group may allow SSH."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.app_from_alb.referenced_security_group_id == aws_security_group.alb.id && aws_vpc_security_group_ingress_rule.app_from_alb.cidr_ipv4 == null
    error_message = "App tier must only accept traffic from the ALB security group."
  }

  assert {
    condition     = aws_vpc_security_group_ingress_rule.endpoints_from_app.referenced_security_group_id == aws_security_group.app.id && aws_vpc_security_group_ingress_rule.data_from_app.referenced_security_group_id == aws_security_group.app.id
    error_message = "Endpoints and data tier must only accept traffic from the app security group."
  }

  assert {
    condition     = length(aws_vpc_security_group_egress_rule.app_internet) == 0
    error_message = "App tier must have no internet egress rule unless egress is allowlisted."
  }

  assert {
    condition     = aws_vpc_security_group_egress_rule.app_to_s3.prefix_list_id == "pl-63a5400a"
    error_message = "S3 access must use the S3 prefix list (gateway endpoint), not 0.0.0.0/0."
  }

  assert {
    condition     = [for r in aws_vpc_security_group_ingress_rule.alb_http : r.cidr_ipv4] == ["203.0.113.10/32"] && length(aws_vpc_security_group_ingress_rule.alb_https) == 0
    error_message = "ALB ingress must honour alb_ingress_cidrs and only open 443 with a certificate."
  }
}

# ---------------------------------------------------------------------------
# VPC endpoints
# ---------------------------------------------------------------------------

run "endpoints_are_private_and_scoped" {
  command = apply

  module {
    source = "../modules/vpc_endpoints"
  }

  variables {
    name                    = "t"
    vpc_id                  = "vpc-12345678"
    region                  = "us-east-1"
    partition               = "aws"
    account_id              = "123456789012"
    subnet_ids              = ["subnet-epa", "subnet-epb"]
    security_group_id       = "sg-endpoints"
    gateway_route_table_ids = ["rtb-appa", "rtb-appb"]
    interface_services      = ["ssm", "ssmmessages", "ec2messages", "logs", "kms"]
  }

  assert {
    condition     = alltrue([for e in aws_vpc_endpoint.interface : e.private_dns_enabled && e.security_group_ids == toset(["sg-endpoints"])])
    error_message = "Interface endpoints need private DNS and the endpoint security group."
  }

  assert {
    condition     = jsondecode(aws_vpc_endpoint.interface["ssm"].policy).Statement[0].Condition.StringEquals["aws:PrincipalAccount"] == "123456789012"
    error_message = "Interface endpoint policies must only allow principals from this account."
  }

  assert {
    condition     = jsondecode(aws_vpc_endpoint.s3.policy).Statement[0].Condition.StringEquals["aws:ResourceAccount"] == "123456789012"
    error_message = "S3 gateway endpoint must only allow this account's buckets (plus AWS package buckets read-only)."
  }

  assert {
    condition     = jsondecode(aws_vpc_endpoint.s3.policy).Statement[1].Action == "s3:GetObject"
    error_message = "AWS-owned package buckets must be read-only."
  }
}

# ---------------------------------------------------------------------------
# Web tier
# ---------------------------------------------------------------------------

run "web_tier_private_hardened_and_waf_protected" {
  command = apply

  module {
    source = "../modules/web_tier"
  }

  variables {
    name                     = "t"
    vpc_id                   = "vpc-12345678"
    region                   = "us-east-1"
    partition                = "aws"
    account_id               = "123456789012"
    ami_id                   = "ami-0123456789abcdef0"
    instance_type            = "t3.micro"
    root_volume_size         = 8
    public_subnet_ids        = ["subnet-puba", "subnet-pubb"]
    app_subnet_ids           = ["subnet-appa", "subnet-appb"]
    alb_sg_id                = "sg-alb"
    app_sg_id                = "sg-app"
    asg_min_size             = 2
    asg_desired_capacity     = 2
    asg_max_size             = 4
    certificate_arn          = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
    web_hostname             = "demo.example.com"
    waf_rate_limit           = 1000
    waf_log_group_name       = "aws-waf-logs-t"
    session_log_group_name   = "/t/ssm/sessions"
    kms_key_arn              = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    log_retention_days       = 30
    alb_logs_expiration_days = 90
    force_destroy            = true
    deletion_protection      = false
  }

  assert {
    condition     = output.web_url == "https://demo.example.com"
    error_message = "With a certificate, web_url must use the certificate's hostname, not the ALB's generated name."
  }

  assert {
    condition     = aws_autoscaling_group.app.vpc_zone_identifier == toset(["subnet-appa", "subnet-appb"]) && aws_lb.this.subnets == toset(["subnet-puba", "subnet-pubb"])
    error_message = "Instances belong in the app tier; only the ALB sits in the public tier."
  }

  assert {
    condition     = aws_launch_template.app.key_name == null || aws_launch_template.app.key_name == ""
    error_message = "No SSH key pair in the advanced profile (Session Manager only)."
  }

  assert {
    condition     = length(aws_launch_template.app.network_interfaces) == 0 && aws_launch_template.app.vpc_security_group_ids == toset(["sg-app"])
    error_message = "Instances must not request a public IP and must use the app SG."
  }

  assert {
    condition     = aws_launch_template.app.metadata_options[0].http_tokens == "required" && aws_launch_template.app.metadata_options[0].http_put_response_hop_limit == 1
    error_message = "IMDSv2 must be required with hop limit 1."
  }

  assert {
    condition     = aws_launch_template.app.block_device_mappings[0].ebs[0].encrypted == "true"
    error_message = "Root volumes must be encrypted."
  }

  assert {
    condition     = aws_lb.this.drop_invalid_header_fields && aws_lb.this.access_logs[0].enabled
    error_message = "ALB must drop invalid headers and write access logs."
  }

  assert {
    condition     = aws_lb_listener.https[0].ssl_policy == "ELBSecurityPolicy-TLS13-1-2-2021-06" && aws_lb_listener.http_redirect[0].default_action[0].type == "redirect" && length(aws_lb_listener.http_forward) == 0
    error_message = "With a certificate: TLS 1.2+/1.3 on 443 and HTTP redirected to HTTPS."
  }

  assert {
    condition     = aws_wafv2_web_acl_association.alb.resource_arn == aws_lb.this.arn
    error_message = "The WAF web ACL must be associated with the ALB."
  }

  assert {
    condition     = length(aws_wafv2_web_acl.this.rule) == 5
    error_message = "Expected four AWS managed rule groups plus the per-IP rate limit."
  }

  assert {
    condition     = contains([for r in aws_wafv2_web_acl.this.rule : r.name], "AWSManagedRulesKnownBadInputsRuleSet")
    error_message = "WAF must include the Known Bad Inputs rule set (covers Log4j / CVE-2021-44228)."
  }

  assert {
    condition     = jsondecode(aws_ssm_document.session.content).inputs.cloudWatchEncryptionEnabled && jsondecode(aws_ssm_document.session.content).inputs.kmsKeyId == "00000000-0000-0000-0000-000000000000"
    error_message = "Session transcripts must be logged encrypted and sessions KMS-encrypted."
  }
}

# ---------------------------------------------------------------------------
# DNS Firewall
# ---------------------------------------------------------------------------

run "dns_firewall_blocks_threats_then_allowlists" {
  command = apply

  module {
    source = "../modules/dns_firewall"
  }

  variables {
    name                    = "t"
    vpc_id                  = "vpc-12345678"
    allowed_domains         = ["amazonaws.com", "GitHub.com."]
    managed_domain_list_ids = ["rslvr-fdl-aaaaaaaaaaaaaaaa", "rslvr-fdl-bbbbbbbbbbbbbbbb"]
    block_unlisted          = true
    fail_open               = false
    query_log_group_name    = "/t/route53-resolver/queries"
    kms_key_arn             = "arn:aws:kms:us-east-1:123456789012:key/00000000-0000-0000-0000-000000000000"
    log_retention_days      = 30
  }

  assert {
    condition     = alltrue([for r in aws_route53_resolver_firewall_rule.managed_block : r.action == "BLOCK" && r.priority < aws_route53_resolver_firewall_rule.allow.priority])
    error_message = "Threat lists must be blocked before the allowlist is evaluated."
  }

  assert {
    condition     = aws_route53_resolver_firewall_rule.block_unlisted[0].priority > aws_route53_resolver_firewall_rule.allow.priority && aws_route53_resolver_firewall_rule.block_unlisted[0].action == "BLOCK"
    error_message = "Walled garden: everything not allowlisted must be blocked last."
  }

  assert {
    condition     = contains(output.allowed_domains, "*.github.com") && contains(output.allowed_domains, "github.com")
    error_message = "Allowlist must cover each domain and its subdomains, normalised."
  }

  assert {
    condition     = aws_route53_resolver_firewall_config.this.firewall_fail_open == "DISABLED"
    error_message = "DNS Firewall must fail closed by default."
  }

  assert {
    condition     = aws_route53_resolver_query_log_config_association.this.resource_id == "vpc-12345678"
    error_message = "Query logging must be associated with the VPC."
  }
}

# ---------------------------------------------------------------------------
# Flow log analytics
# ---------------------------------------------------------------------------

run "athena_table_matches_flow_log_format" {
  command = apply

  module {
    source = "../modules/flow_log_analytics"
  }

  variables {
    name                 = "securevpc-adv"
    bucket_name          = "securevpc-adv-flow-logs"
    account_id           = "123456789012"
    region               = "us-east-1"
    fields               = ["version", "srcaddr", "dstport", "tcp-flags", "flow-direction", "traffic-path"]
    kms_key_arn          = null
    bytes_scanned_cutoff = 10485760
  }

  assert {
    condition     = [for c in aws_glue_catalog_table.flow_logs.storage_descriptor[0].columns : c.name] == ["version", "srcaddr", "dstport", "tcp_flags", "flow_direction", "traffic_path"]
    error_message = "Athena columns must follow the flow log field order, with hyphens as underscores."
  }

  assert {
    condition     = aws_glue_catalog_table.flow_logs.parameters["projection.enabled"] == "true" && strcontains(aws_glue_catalog_table.flow_logs.storage_descriptor[0].location, "aws-account-id=123456789012/aws-service=vpcflowlogs/aws-region=us-east-1/")
    error_message = "Table must use partition projection over the Hive-style flow log prefix."
  }

  assert {
    condition     = aws_athena_workgroup.this.configuration[0].enforce_workgroup_configuration && aws_athena_workgroup.this.configuration[0].bytes_scanned_cutoff_per_query == 10485760
    error_message = "Workgroup must enforce its settings and cap bytes scanned per query."
  }

  assert {
    condition     = aws_glue_catalog_database.this.name == "securevpc_adv_flowlogs"
    error_message = "Glue database name must be a valid identifier."
  }
}
