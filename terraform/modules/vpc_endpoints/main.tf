# Private paths to the AWS APIs the app tier needs, so none of that traffic
# touches the internet. Endpoint policies add a data perimeter:
#   - interface endpoints: only principals from this account
#   - S3 gateway endpoint: only this account's buckets, plus read-only access
#     to the AWS-owned buckets that host Amazon Linux packages and the SSM agent

locals {
  # Services that accept a custom endpoint policy. The SSM channel endpoints
  # (ssmmessages, ec2messages) keep the default policy.
  policy_services = ["ssm", "logs", "kms", "sts", "monitoring"]

  aws_owned_read_buckets = [
    "al2023-repos-${var.region}-de612dc2",
    "amazon-ssm-${var.region}",
    "amazon-ssm-packages-${var.region}",
    "aws-ssm-${var.region}",
    "${var.region}-birdwatcher-prod",
    "patch-baseline-snapshot-${var.region}",
  ]
}

resource "aws_vpc_endpoint" "interface" {
  for_each = toset(var.interface_services)

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  private_dns_enabled = true
  subnet_ids          = var.subnet_ids
  security_group_ids  = [var.security_group_id]

  policy = contains(local.policy_services, each.value) ? jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "OnlyThisAccount"
      Effect    = "Allow"
      Principal = "*"
      Action    = "*"
      Resource  = "*"
      Condition = { StringEquals = { "aws:PrincipalAccount" = var.account_id } }
    }]
  }) : null

  tags = { Name = "${var.name}-${each.value}-endpoint" }
}

resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.gateway_route_table_ids

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "OwnAccountBuckets"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:*"
        Resource  = "*"
        Condition = { StringEquals = { "aws:ResourceAccount" = var.account_id } }
      },
      {
        Sid       = "AwsOwnedPackageBuckets"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = [for b in local.aws_owned_read_buckets : "arn:${var.partition}:s3:::${b}/*"]
      },
    ]
  })

  tags = { Name = "${var.name}-s3-endpoint" }
}
