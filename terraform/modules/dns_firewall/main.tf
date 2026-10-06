# Route 53 Resolver DNS Firewall. Rule priority (lowest first):
#   100+  BLOCK  AWS Managed Domain Lists (threat intel), even under allowed domains
#   500   ALLOW  allowed_domains (AWS service endpoints + the egress allowlist)
#   900   BLOCK  "*" when block_unlisted (walled garden: stops DNS tunnelling
#                and exfiltration to arbitrary domains)
# Every query, allowed or blocked, lands in CloudWatch via query logging.

locals {
  allowed = distinct(flatten([for d in var.allowed_domains : [
    lower(trimprefix(trimsuffix(d, "."), ".")),
    "*.${lower(trimprefix(trimsuffix(d, "."), "."))}",
  ]]))
}

resource "aws_route53_resolver_firewall_domain_list" "allowed" {
  name    = "${var.name}-allowed"
  domains = local.allowed

  tags = { Name = "${var.name}-dns-allowed" }
}

resource "aws_route53_resolver_firewall_domain_list" "everything" {
  count = var.block_unlisted ? 1 : 0

  name    = "${var.name}-everything"
  domains = ["*"]

  tags = { Name = "${var.name}-dns-everything" }
}

resource "aws_route53_resolver_firewall_rule_group" "this" {
  name = "${var.name}-dns-firewall"

  tags = { Name = "${var.name}-dns-firewall" }
}

resource "aws_route53_resolver_firewall_rule" "managed_block" {
  for_each = { for i, id in var.managed_domain_list_ids : id => i }

  name                    = "${var.name}-managed-${each.value}"
  action                  = "BLOCK"
  block_response          = "NXDOMAIN"
  firewall_domain_list_id = each.key
  firewall_rule_group_id  = aws_route53_resolver_firewall_rule_group.this.id
  priority                = 100 + each.value
}

resource "aws_route53_resolver_firewall_rule" "allow" {
  name                    = "${var.name}-allow"
  action                  = "ALLOW"
  firewall_domain_list_id = aws_route53_resolver_firewall_domain_list.allowed.id
  firewall_rule_group_id  = aws_route53_resolver_firewall_rule_group.this.id
  priority                = 500
}

resource "aws_route53_resolver_firewall_rule" "block_unlisted" {
  count = var.block_unlisted ? 1 : 0

  name                    = "${var.name}-block-unlisted"
  action                  = "BLOCK"
  block_response          = "NXDOMAIN"
  firewall_domain_list_id = aws_route53_resolver_firewall_domain_list.everything[0].id
  firewall_rule_group_id  = aws_route53_resolver_firewall_rule_group.this.id
  priority                = 900
}

resource "aws_route53_resolver_firewall_rule_group_association" "this" {
  name                   = "${var.name}-dns-firewall"
  firewall_rule_group_id = aws_route53_resolver_firewall_rule_group.this.id
  vpc_id                 = var.vpc_id
  priority               = 101
  mutation_protection    = "DISABLED"

  depends_on = [
    aws_route53_resolver_firewall_rule.managed_block,
    aws_route53_resolver_firewall_rule.allow,
    aws_route53_resolver_firewall_rule.block_unlisted,
  ]
}

resource "aws_route53_resolver_firewall_config" "this" {
  resource_id        = var.vpc_id
  firewall_fail_open = var.fail_open ? "ENABLED" : "DISABLED"
}

# ---------------------------------------------------------------------------
# Query logging
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "queries" {
  #checkov:skip=CKV_AWS_338:Retention is a variable; the default keeps a lab cheap.
  name              = var.query_log_group_name
  retention_in_days = var.log_retention_days
  kms_key_id        = var.kms_key_arn
}

resource "aws_route53_resolver_query_log_config" "this" {
  name            = "${var.name}-dns-queries"
  destination_arn = aws_cloudwatch_log_group.queries.arn

  tags = { Name = "${var.name}-dns-queries" }
}

resource "aws_route53_resolver_query_log_config_association" "this" {
  resolver_query_log_config_id = aws_route53_resolver_query_log_config.this.id
  resource_id                  = var.vpc_id
}
