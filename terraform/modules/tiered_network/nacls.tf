# Stateless subnet-level backstop. Security groups (tier_security module) are
# the primary control; these NACLs bound which ports can cross each tier
# boundary at all, so one bad SG rule cannot open a tier on its own.

locals {
  ephemeral_from = 1024
  ephemeral_to   = 65535

  public_in = {
    https     = { port_from = 443, port_to = 443, rule = 100 }
    http      = { port_from = 80, port_to = 80, rule = 110 }
    ephemeral = { port_from = local.ephemeral_from, port_to = local.ephemeral_to, rule = 200 }
  }

  app_cidr_list = [for az in var.azs : local.app_cidrs[az]]
  pub_cidr_list = [for az in var.azs : local.public_cidrs[az]]
}

# ---------------------------------------------------------------------------
# Firewall subnets: AWS recommends leaving these open; the firewall itself
# is the control, and asymmetric NACLs here break inspection.
# ---------------------------------------------------------------------------

resource "aws_network_acl" "firewall" {
  count = var.enable_firewall_subnets ? 1 : 0

  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.firewall : s.id]

  tags = { Name = "${var.name}-firewall-nacl" }
}

resource "aws_network_acl_rule" "firewall_in_all" {
  #checkov:skip=CKV_AWS_229:Firewall subnets only host Network Firewall endpoints, which inspect every packet; AWS guidance is to not filter here.
  #checkov:skip=CKV_AWS_230:See CKV_AWS_229.
  #checkov:skip=CKV_AWS_231:See CKV_AWS_229.
  #checkov:skip=CKV_AWS_232:See CKV_AWS_229.
  #checkov:skip=CKV_AWS_352:See CKV_AWS_229.
  count = var.enable_firewall_subnets ? 1 : 0

  network_acl_id = aws_network_acl.firewall[0].id
  rule_number    = 100
  egress         = false
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

resource "aws_network_acl_rule" "firewall_out_all" {
  count = var.enable_firewall_subnets ? 1 : 0

  network_acl_id = aws_network_acl.firewall[0].id
  rule_number    = 100
  egress         = true
  protocol       = "-1"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# Public tier: ALB listeners, NAT forwarding, return traffic
# ---------------------------------------------------------------------------

resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.public : s.id]

  tags = { Name = "${var.name}-public-nacl" }
}

resource "aws_network_acl_rule" "public_in" {
  #checkov:skip=CKV_AWS_231:Ephemeral return range; nothing in the public tier listens on 3389 and the ALB SG only opens 80/443.
  #checkov:skip=CKV_AWS_232:Ephemeral return range; nothing in the public tier listens on 20/21.
  for_each = local.public_in

  network_acl_id = aws_network_acl.public.id
  rule_number    = each.value.rule
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = each.value.port_from
  to_port        = each.value.port_to
}

resource "aws_network_acl_rule" "public_out" {
  for_each = local.public_in

  network_acl_id = aws_network_acl.public.id
  rule_number    = each.value.rule
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = each.value.port_from
  to_port        = each.value.port_to
}

# ---------------------------------------------------------------------------
# App tier: HTTP only from the public tier (ALB); egress 80/443 + data port
# ---------------------------------------------------------------------------

resource "aws_network_acl" "app" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.app : s.id]

  tags = { Name = "${var.name}-app-nacl" }
}

resource "aws_network_acl_rule" "app_in_http_from_public" {
  count = length(local.pub_cidr_list)

  network_acl_id = aws_network_acl.app.id
  rule_number    = 100 + count.index
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = local.pub_cidr_list[count.index]
  from_port      = 80
  to_port        = 80
}

# Replies from NAT egress, VPC endpoints and the data tier.
resource "aws_network_acl_rule" "app_in_ephemeral" {
  #checkov:skip=CKV_AWS_231:Ephemeral return range; app instances have no public IPs and SGs deny unsolicited inbound.
  #checkov:skip=CKV_AWS_232:Ephemeral return range; no service listens on 20/21.
  network_acl_id = aws_network_acl.app.id
  rule_number    = 200
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = local.ephemeral_from
  to_port        = local.ephemeral_to
}

resource "aws_network_acl_rule" "app_out_https" {
  network_acl_id = aws_network_acl.app.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "app_out_http" {
  network_acl_id = aws_network_acl.app.id
  rule_number    = 110
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "app_out_data" {
  count = length(var.azs)

  network_acl_id = aws_network_acl.app.id
  rule_number    = 200 + count.index
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = local.data_cidrs[var.azs[count.index]]
  from_port      = var.data_port
  to_port        = var.data_port
}

resource "aws_network_acl_rule" "app_out_ephemeral_to_public" {
  count = length(local.pub_cidr_list)

  network_acl_id = aws_network_acl.app.id
  rule_number    = 300 + count.index
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = local.pub_cidr_list[count.index]
  from_port      = local.ephemeral_from
  to_port        = local.ephemeral_to
}

# ---------------------------------------------------------------------------
# Endpoint tier: HTTPS from the app tier only
# ---------------------------------------------------------------------------

resource "aws_network_acl" "endpoint" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.endpoint : s.id]

  tags = { Name = "${var.name}-endpoints-nacl" }
}

resource "aws_network_acl_rule" "endpoint_in_https_from_app" {
  count = length(local.app_cidr_list)

  network_acl_id = aws_network_acl.endpoint.id
  rule_number    = 100 + count.index
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = local.app_cidr_list[count.index]
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "endpoint_out_ephemeral_to_app" {
  count = length(local.app_cidr_list)

  network_acl_id = aws_network_acl.endpoint.id
  rule_number    = 100 + count.index
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = local.app_cidr_list[count.index]
  from_port      = local.ephemeral_from
  to_port        = local.ephemeral_to
}

# ---------------------------------------------------------------------------
# Data tier: the data port from the app tier, replies to the app tier, nothing else
# ---------------------------------------------------------------------------

resource "aws_network_acl" "data" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = [for s in aws_subnet.data : s.id]

  tags = { Name = "${var.name}-data-nacl" }
}

resource "aws_network_acl_rule" "data_in_from_app" {
  count = length(local.app_cidr_list)

  network_acl_id = aws_network_acl.data.id
  rule_number    = 100 + count.index
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = local.app_cidr_list[count.index]
  from_port      = var.data_port
  to_port        = var.data_port
}

resource "aws_network_acl_rule" "data_out_ephemeral_to_app" {
  count = length(local.app_cidr_list)

  network_acl_id = aws_network_acl.data.id
  rule_number    = 100 + count.index
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = local.app_cidr_list[count.index]
  from_port      = local.ephemeral_from
  to_port        = local.ephemeral_to
}
