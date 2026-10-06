# AWS Network Firewall between the Internet Gateway and the public subnets
# ("IGW + NAT" deployment model). Inbound traffic to the ALB and outbound
# traffic from the NAT Gateways both cross the same-AZ firewall endpoint:
#
#   IGW edge RT:   public subnet CIDR -> firewall endpoint (same AZ)
#   public RT:     0.0.0.0/0          -> firewall endpoint (same AZ)
#   firewall RT:   0.0.0.0/0          -> IGW
#
# Rules use STRICT_ORDER with drop_established as the default action, so
# anything not explicitly passed is dropped and logged.

locals {
  domains = distinct([for d in var.egress_allowed_domains : lower(trimprefix(trimsuffix(d, "."), "."))])

  domain_rules = flatten([for i, d in local.domains : [
    "pass tls $HOME_NET any -> $EXTERNAL_NET 443 (tls.sni; dotprefix; content:\".${d}\"; nocase; endswith; flow:to_server, established; msg:\"SecureVPC egress allow TLS ${d}\"; sid:${2000 + i * 2}; rev:1;)",
    "pass http $HOME_NET any -> $EXTERNAL_NET 80 (http.host; dotprefix; content:\".${d}\"; endswith; flow:to_server, established; msg:\"SecureVPC egress allow HTTP ${d}\"; sid:${2001 + i * 2}; rev:1;)",
  ]])

  rules = concat(
    [
      "pass tcp $EXTERNAL_NET any -> $ALB_NET [80,443] (flow:to_server; msg:\"SecureVPC ingress to ALB listeners\"; sid:1000; rev:1;)",
      "pass tcp $HOME_NET any -> $EXTERNAL_NET [80,443] (flow:not_established, to_server; msg:\"SecureVPC egress TCP handshake\"; sid:1001; rev:1;)",
      "pass tcp $EXTERNAL_NET [80,443] -> $HOME_NET any (flow:not_established, to_client; msg:\"SecureVPC egress TCP handshake reply\"; sid:1002; rev:1;)",
    ],
    local.domain_rules,
    [
      "drop tls $HOME_NET any -> $EXTERNAL_NET any (flow:to_server, established; msg:\"SecureVPC egress TLS to non-allowlisted SNI\"; sid:9001; rev:1;)",
      "drop http $HOME_NET any -> $EXTERNAL_NET any (flow:to_server, established; msg:\"SecureVPC egress HTTP to non-allowlisted host\"; sid:9002; rev:1;)",
      "drop tcp $HOME_NET any -> $EXTERNAL_NET ![80,443] (flow:to_server; msg:\"SecureVPC egress TCP port not allowed\"; sid:9003; rev:1;)",
      "drop udp $HOME_NET any -> $EXTERNAL_NET any (msg:\"SecureVPC egress UDP not allowed\"; sid:9004; rev:1;)",
      "drop icmp $HOME_NET any -> $EXTERNAL_NET any (msg:\"SecureVPC egress ICMP not allowed\"; sid:9005; rev:1;)",
      "drop tcp $EXTERNAL_NET any -> $HOME_NET any (flow:to_server; msg:\"SecureVPC ingress not to ALB listeners\"; sid:9006; rev:1;)",
    ],
  )

  endpoint_ids = {
    for s in tolist(aws_networkfirewall_firewall.this.firewall_status[0].sync_states) :
    s.availability_zone => s.attachment[0].endpoint_id
  }
}

resource "aws_networkfirewall_rule_group" "segmentation" {
  name     = "${var.name}-segmentation"
  type     = "STATEFUL"
  capacity = 200

  encryption_configuration {
    key_id = var.kms_key_arn
    type   = "CUSTOMER_KMS"
  }

  rule_group {
    rule_variables {
      ip_sets {
        key = "HOME_NET"
        ip_set {
          definition = [var.vpc_cidr]
        }
      }
      ip_sets {
        key = "ALB_NET"
        ip_set {
          definition = values(var.public_subnet_cidrs)
        }
      }
    }

    rules_source {
      rules_string = join("\n", local.rules)
    }

    stateful_rule_options {
      rule_order = "STRICT_ORDER"
    }
  }

  tags = { Name = "${var.name}-segmentation" }
}

resource "aws_networkfirewall_firewall_policy" "this" {
  name = "${var.name}-policy"

  encryption_configuration {
    key_id = var.kms_key_arn
    type   = "CUSTOMER_KMS"
  }

  firewall_policy {
    stateless_default_actions          = ["aws:forward_to_sfe"]
    stateless_fragment_default_actions = ["aws:forward_to_sfe"]
    stateful_default_actions           = ["aws:drop_established", "aws:alert_established"]

    stateful_engine_options {
      rule_order              = "STRICT_ORDER"
      stream_exception_policy = "DROP"
    }

    # Threat intelligence first, so a known-bad destination is dropped even
    # if it sits under an allowlisted domain.
    dynamic "stateful_rule_group_reference" {
      for_each = { for i, n in var.managed_rule_groups : n => i }
      content {
        priority     = 10 + stateful_rule_group_reference.value * 10
        resource_arn = "arn:${var.partition}:network-firewall:${var.region}:aws-managed:stateful-rulegroup/${stateful_rule_group_reference.key}"
      }
    }

    stateful_rule_group_reference {
      priority     = 1000
      resource_arn = aws_networkfirewall_rule_group.segmentation.arn
    }
  }

  tags = { Name = "${var.name}-policy" }
}

resource "aws_networkfirewall_firewall" "this" {
  #checkov:skip=CKV_AWS_344:Deletion protection is a variable (delete_protection); off by default so the lab can be torn down in one command.
  name                              = "${var.name}-fw"
  vpc_id                            = var.vpc_id
  firewall_policy_arn               = aws_networkfirewall_firewall_policy.this.arn
  delete_protection                 = var.delete_protection
  firewall_policy_change_protection = false
  subnet_change_protection          = false

  dynamic "subnet_mapping" {
    for_each = var.firewall_subnet_ids
    content {
      subnet_id = subnet_mapping.value
    }
  }

  encryption_configuration {
    key_id = var.kms_key_arn
    type   = "CUSTOMER_KMS"
  }

  tags = { Name = "${var.name}-fw" }
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "alert" {
  #checkov:skip=CKV_AWS_338:Retention is a variable; the default keeps a lab cheap.
  name              = var.alert_log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_cloudwatch_log_group" "flow" {
  #checkov:skip=CKV_AWS_338:Retention is a variable; the default keeps a lab cheap.
  name              = var.flow_log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_networkfirewall_logging_configuration" "this" {
  firewall_arn = aws_networkfirewall_firewall.this.arn

  logging_configuration {
    log_destination_config {
      log_type             = "ALERT"
      log_destination_type = "CloudWatchLogs"
      log_destination      = { logGroup = aws_cloudwatch_log_group.alert.name }
    }

    log_destination_config {
      log_type             = "FLOW"
      log_destination_type = "CloudWatchLogs"
      log_destination      = { logGroup = aws_cloudwatch_log_group.flow.name }
    }
  }
}

# ---------------------------------------------------------------------------
# Routing through the firewall
# ---------------------------------------------------------------------------

resource "aws_route" "firewall_to_igw" {
  route_table_id         = var.firewall_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = var.igw_id
}

resource "aws_route" "public_via_firewall" {
  for_each = var.public_route_table_ids

  route_table_id         = each.value
  destination_cidr_block = "0.0.0.0/0"
  vpc_endpoint_id        = local.endpoint_ids[each.key]
}

resource "aws_route_table" "igw_edge" {
  vpc_id = var.vpc_id

  tags = { Name = "${var.name}-igw-edge-rt" }
}

resource "aws_route" "igw_edge_to_firewall" {
  for_each = var.public_subnet_cidrs

  route_table_id         = aws_route_table.igw_edge.id
  destination_cidr_block = each.value
  vpc_endpoint_id        = local.endpoint_ids[each.key]
}

resource "aws_route_table_association" "igw_edge" {
  gateway_id     = var.igw_id
  route_table_id = aws_route_table.igw_edge.id
}
