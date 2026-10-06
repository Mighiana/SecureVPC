# Security groups reference each other, so every allowed hop is expressed as
# "role -> role" rather than "IP -> IP":
#
#   internet --80/443--> alb --80--> app --443--> endpoints
#                                    app --443--> S3 (prefix list, gateway endpoint)
#                                    app --data_port--> data
#
# Nothing has SSH. Admin access is SSM Session Manager over the endpoints.

data "aws_ec2_managed_prefix_list" "s3" {
  name = "com.amazonaws.${var.region}.s3"
}

resource "aws_security_group" "alb" {
  #checkov:skip=CKV2_AWS_5:Attached to the ALB in the web_tier module; checkov does not follow the cross-module reference.
  name        = "${var.name}-alb-sg"
  description = "Public ALB: HTTP/HTTPS in, HTTP to the app tier only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-alb-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "app" {
  #checkov:skip=CKV2_AWS_5:Attached via the launch template in the web_tier module; checkov does not follow the cross-module reference.
  name        = "${var.name}-app-sg"
  description = "App tier: HTTP from the ALB only, no SSH"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-app-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "endpoints" {
  #checkov:skip=CKV2_AWS_5:Attached to the interface endpoints in the vpc_endpoints module; checkov does not follow the cross-module reference.
  name        = "${var.name}-endpoints-sg"
  description = "Interface VPC endpoints: HTTPS from the app tier only"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-endpoints-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "data" {
  #checkov:skip=CKV2_AWS_5:Reserved for the data tier (no database is deployed by this project).
  name        = "${var.name}-data-sg"
  description = "Data tier: data port from the app tier only, no egress"
  vpc_id      = var.vpc_id

  tags = { Name = "${var.name}-data-sg" }

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# ALB
# ---------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  #checkov:skip=CKV_AWS_260:The ALB is the intended public entry point; WAF and the firewall sit in front of it.
  for_each = toset(var.alb_ingress_cidrs)

  security_group_id = aws_security_group.alb.id
  description       = "HTTP to the ALB"
  ip_protocol       = "tcp"
  from_port         = 80
  to_port           = 80
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  for_each = var.enable_https ? toset(var.alb_ingress_cidrs) : toset([])

  security_group_id = aws_security_group.alb.id
  description       = "HTTPS to the ALB"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value
}

resource "aws_vpc_security_group_egress_rule" "alb_to_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "HTTP to app targets"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.app.id
}

# ---------------------------------------------------------------------------
# App tier
# ---------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "app_from_alb" {
  #checkov:skip=CKV_AWS_260:False positive: source is the ALB security group, not a CIDR (covered by tests).
  security_group_id            = aws_security_group.app.id
  description                  = "HTTP from the ALB only"
  ip_protocol                  = "tcp"
  from_port                    = 80
  to_port                      = 80
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_egress_rule" "app_to_endpoints" {
  security_group_id            = aws_security_group.app.id
  description                  = "HTTPS to interface VPC endpoints (SSM, Logs, KMS)"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.endpoints.id
}

resource "aws_vpc_security_group_egress_rule" "app_to_s3" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS to S3 via the gateway endpoint (OS packages)"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = data.aws_ec2_managed_prefix_list.s3.id
}

resource "aws_vpc_security_group_egress_rule" "app_to_data" {
  security_group_id            = aws_security_group.app.id
  description                  = "Data tier port"
  ip_protocol                  = "tcp"
  from_port                    = var.data_port
  to_port                      = var.data_port
  referenced_security_group_id = aws_security_group.data.id
}

resource "aws_vpc_security_group_egress_rule" "app_internet" {
  for_each = var.allow_internet_egress ? { http = 80, https = 443 } : {}

  security_group_id = aws_security_group.app.id
  description       = "Internet ${upper(each.key)} via NAT (domain allowlist enforced by Network Firewall)"
  ip_protocol       = "tcp"
  from_port         = each.value
  to_port           = each.value
  cidr_ipv4         = "0.0.0.0/0"
}

# ---------------------------------------------------------------------------
# Endpoints and data tier (ingress only; no egress rules at all)
# ---------------------------------------------------------------------------

resource "aws_vpc_security_group_ingress_rule" "endpoints_from_app" {
  security_group_id            = aws_security_group.endpoints.id
  description                  = "HTTPS from the app tier"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_vpc_security_group_ingress_rule" "data_from_app" {
  security_group_id            = aws_security_group.data.id
  description                  = "Data port from the app tier"
  ip_protocol                  = "tcp"
  from_port                    = var.data_port
  to_port                      = var.data_port
  referenced_security_group_id = aws_security_group.app.id
}
