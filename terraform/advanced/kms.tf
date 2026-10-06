# One customer-managed key for this profile's logs, firewall, SNS and SSM
# sessions. (The flow_logs module keeps its own key, as in the original profile.)

resource "aws_kms_key" "this" {
  description             = "${local.name} logs, firewall, alarms and SSM sessions"
  deletion_window_in_days = 7
  enable_key_rotation     = true

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministration"
        Effect    = "Allow"
        Principal = { AWS = "arn:${local.partition}:iam::${local.account}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "CloudWatchLogsForThisProfile"
        Effect    = "Allow"
        Principal = { Service = "logs.${local.region}.amazonaws.com" }
        Action    = ["kms:Encrypt*", "kms:Decrypt*", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:Describe*"]
        Resource  = "*"
        Condition = {
          ArnLike = {
            "kms:EncryptionContext:aws:logs:arn" = [
              "arn:${local.partition}:logs:${local.region}:${local.account}:log-group:/${local.name}/*",
              "arn:${local.partition}:logs:${local.region}:${local.account}:log-group:${local.log_groups.waf}",
            ]
          }
        }
      },
      {
        Sid       = "CloudWatchAlarmsToEncryptedSns"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:SourceAccount" = local.account } }
      },
    ]
  })
}

resource "aws_kms_alias" "this" {
  name          = "alias/${local.name}"
  target_key_id = aws_kms_key.this.key_id
}

# Network Firewall, WAF and Resolver query logging deliver through the
# CloudWatch vended-logs service. Scope that delivery to this profile's
# log groups instead of relying on the auto-created account-wide policy.
resource "aws_cloudwatch_log_resource_policy" "vended_logs" {
  policy_name = "${local.name}-vended-log-delivery"

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "VendedLogDelivery"
      Effect    = "Allow"
      Principal = { Service = ["delivery.logs.amazonaws.com", "route53.amazonaws.com"] }
      Action    = ["logs:CreateLogStream", "logs:PutLogEvents"]
      Resource = [
        "arn:${local.partition}:logs:${local.region}:${local.account}:log-group:/${local.name}/*:*",
        "arn:${local.partition}:logs:${local.region}:${local.account}:log-group:${local.log_groups.waf}:*",
      ]
      Condition = {
        StringEquals = { "aws:SourceAccount" = local.account }
        ArnLike      = { "aws:SourceArn" = "arn:${local.partition}:*:${local.region}:${local.account}:*" }
      }
    }]
  })
}
