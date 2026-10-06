# Security groups are stateful: only the initiating direction needs a rule.
# Instance-to-instance rules reference security groups, not CIDRs, so access
# follows the role of the instance rather than its IP.

resource "aws_security_group" "bastion" {
  #checkov:skip=CKV2_AWS_5:Attached to aws_instance.bastion in the compute module; checkov does not follow the cross-module reference.
  name        = "${var.name}-bastion-sg"
  description = "Bastion host: SSH in from admin CIDRs only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-bastion-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "web" {
  #checkov:skip=CKV2_AWS_5:Attached to aws_instance.web in the compute module; checkov does not follow the cross-module reference.
  name        = "${var.name}-web-sg"
  description = "Private web server: SSH and HTTP from the bastion SG only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-web-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Bastion
# ---------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "bastion_ssh_admin" {
  for_each = toset(var.admin_cidrs)

  security_group_id = aws_security_group.bastion.id
  description       = "SSH from admin CIDR"
  ip_protocol       = "tcp"
  from_port         = 22
  to_port           = 22
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "bastion_ssh_to_web" {
  security_group_id            = aws_security_group.bastion.id
  description                  = "SSH to private web server"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.web.id
}

resource "aws_vpc_security_group_egress_rule" "bastion_http_to_web" {
  security_group_id            = aws_security_group.bastion.id
  description                  = "HTTP to private web server (validation)"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.web.id
}

resource "aws_vpc_security_group_egress_rule" "bastion_https_out" {
  security_group_id = aws_security_group.bastion.id
  description       = "HTTPS out for OS package updates"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# Web server
# ---------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "web_ssh_from_bastion" {
  #checkov:skip=CKV_AWS_24:False positive: source is the bastion security group, not a CIDR (covered by tests/securevpc.tftest.hcl).
  security_group_id            = aws_security_group.web.id
  description                  = "SSH from bastion only"
  ip_protocol                  = "tcp"
  from_port                    = 22
  to_port                      = 22
  referenced_security_group_id = aws_security_group.bastion.id
}

resource "aws_vpc_security_group_ingress_rule" "web_http_from_bastion" {
  #checkov:skip=CKV_AWS_260:False positive: source is the bastion security group, not a CIDR (covered by tests/securevpc.tftest.hcl).
  security_group_id            = aws_security_group.web.id
  description                  = "HTTP from bastion only"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.bastion.id
}

resource "aws_vpc_security_group_egress_rule" "web_http_out" {
  security_group_id = aws_security_group.web.id
  description       = "HTTP out via NAT Gateway (package repos)"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_egress_rule" "web_https_out" {
  security_group_id = aws_security_group.web.id
  description       = "HTTPS out via NAT Gateway (package repos)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}
