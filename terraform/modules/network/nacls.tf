# Network ACLs are stateless, so every allowed flow needs an explicit rule in
# both directions. Security groups (stateful, see the security module) are the
# primary instance-level control; the NACLs below are a coarser subnet-level
# backstop that limits which ports can cross each subnet boundary at all.

locals {
  ephemeral_from = 1024
  ephemeral_to   = 65535
}

# ---------------------------------------------------------------------------
# Public subnet NACL
# ---------------------------------------------------------------------------

resource "aws_network_acl" "public" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = [aws_subnet.public.id]

  tags = { Name = "${var.name}-public-nacl" }
}

# Inbound SSH to the bastion, admin CIDRs only.
resource "aws_network_acl_rule" "public_in_ssh_admin" {
  count = length(var.admin_cidrs)

  network_acl_id = aws_network_acl.public.id
  rule_number    = 100 + count.index
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.admin_cidrs[count.index]
  from_port      = 22
  to_port        = 22
}

# Private-subnet HTTP/HTTPS headed to the internet through the NAT Gateway.
resource "aws_network_acl_rule" "public_in_http_from_private" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 200
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.private_subnet_cidr
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "public_in_https_from_private" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 210
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.private_subnet_cidr
  from_port      = 443
  to_port        = 443
}

# Return traffic (internet replies to the bastion/NAT, private-subnet replies
# to the bastion's SSH/HTTP sessions).
resource "aws_network_acl_rule" "public_in_ephemeral" {
  #checkov:skip=CKV_AWS_231:Stateless return-traffic range; the bastion SG only listens on 22 from admin CIDRs, so 3389 is never served.
  #checkov:skip=CKV_AWS_232:Stateless return-traffic range; no service listens on port 20/21 and SGs deny it.
  network_acl_id = aws_network_acl.public.id
  rule_number    = 300
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = local.ephemeral_from
  to_port        = local.ephemeral_to
}

resource "aws_network_acl_rule" "public_out_ssh_to_private" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 100
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.private_subnet_cidr
  from_port      = 22
  to_port        = 22
}

resource "aws_network_acl_rule" "public_out_http" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 200
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "public_out_https" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 210
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

resource "aws_network_acl_rule" "public_out_ephemeral" {
  network_acl_id = aws_network_acl.public.id
  rule_number    = 300
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = local.ephemeral_from
  to_port        = local.ephemeral_to
}

# ---------------------------------------------------------------------------
# Private subnet NACL
# ---------------------------------------------------------------------------

resource "aws_network_acl" "private" {
  vpc_id     = aws_vpc.this.id
  subnet_ids = [aws_subnet.private.id]

  tags = { Name = "${var.name}-private-nacl" }
}

# Only the public subnet (bastion) may open SSH/HTTP into the private subnet.
resource "aws_network_acl_rule" "private_in_ssh_from_public" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 100
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.public_subnet_cidr
  from_port      = 22
  to_port        = 22
}

resource "aws_network_acl_rule" "private_in_http_from_public" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 110
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.public_subnet_cidr
  from_port      = 80
  to_port        = 80
}

# Replies to outbound connections the web server made through the NAT.
resource "aws_network_acl_rule" "private_in_ephemeral" {
  #checkov:skip=CKV_AWS_231:Stateless return-traffic range for NAT egress; instances have no public IPs and SGs deny unsolicited inbound.
  #checkov:skip=CKV_AWS_232:Stateless return-traffic range for NAT egress; no service listens on port 20/21.
  network_acl_id = aws_network_acl.private.id
  rule_number    = 300
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = local.ephemeral_from
  to_port        = local.ephemeral_to
}

resource "aws_network_acl_rule" "private_out_http" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 200
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 80
  to_port        = 80
}

resource "aws_network_acl_rule" "private_out_https" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 210
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = "0.0.0.0/0"
  from_port      = 443
  to_port        = 443
}

# Replies to the bastion's SSH/HTTP sessions only — not to the internet.
resource "aws_network_acl_rule" "private_out_ephemeral_to_public" {
  network_acl_id = aws_network_acl.private.id
  rule_number    = 300
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.public_subnet_cidr
  from_port      = local.ephemeral_from
  to_port        = local.ephemeral_to
}
