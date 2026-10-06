# Security alarms -> encrypted SNS topic -> (optional) email.

resource "aws_sns_topic" "alerts" {
  name              = "${local.name}-security-alerts"
  kms_master_key_id = aws_kms_key.this.arn
}

resource "aws_sns_topic_policy" "alerts" {
  arn = aws_sns_topic.alerts.arn

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "CloudWatchAlarmsOnly"
        Effect    = "Allow"
        Principal = { Service = "cloudwatch.amazonaws.com" }
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.alerts.arn
        Condition = {
          StringEquals = { "aws:SourceAccount" = local.account }
          ArnLike      = { "aws:SourceArn" = "arn:${local.partition}:cloudwatch:${local.region}:${local.account}:alarm:${local.name}-*" }
        }
      },
      {
        Sid       = "DenyInsecureTransport"
        Effect    = "Deny"
        Principal = "*"
        Action    = "sns:Publish"
        Resource  = aws_sns_topic.alerts.arn
        Condition = { Bool = { "aws:SecureTransport" = "false" } }
      },
    ]
  })
}

resource "aws_sns_topic_subscription" "email" {
  count = var.alert_email == null ? 0 : 1

  topic_arn = aws_sns_topic.alerts.arn
  protocol  = "email"
  endpoint  = var.alert_email
}

# ---------------------------------------------------------------------------
# Metric filters on the firewall and DNS logs
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_metric_filter" "firewall_blocked" {
  count = var.enable_network_firewall ? 1 : 0

  name           = "${local.name}-firewall-blocked"
  log_group_name = module.firewall[0].alert_log_group_name
  pattern        = "{ $.event.alert.action = \"blocked\" }"

  metric_transformation {
    name          = "FirewallBlocked"
    namespace     = "SecureVPC/${local.name}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_log_metric_filter" "dns_blocked" {
  count = var.enable_dns_firewall ? 1 : 0

  name           = "${local.name}-dns-firewall-blocked"
  log_group_name = module.dns_firewall[0].query_log_group_name
  pattern        = "{ $.firewall_rule_action = \"BLOCK\" }"

  metric_transformation {
    name          = "DnsFirewallBlocked"
    namespace     = "SecureVPC/${local.name}"
    value         = "1"
    default_value = "0"
  }
}

# ---------------------------------------------------------------------------
# Alarms
# ---------------------------------------------------------------------------

locals {
  alarms = merge(
    {
      rejected-flows = {
        description = "VPC Flow Logs: rejected flows above threshold (scanning or misconfigured SG/NACL)"
        namespace   = "SecureVPC/${local.name}"
        metric      = "RejectedFlows"
        dimensions  = {}
        threshold   = var.rejected_flows_threshold
      }
      waf-blocked = {
        description = "WAF blocked requests on the ALB"
        namespace   = "AWS/WAFV2"
        metric      = "BlockedRequests"
        dimensions  = { WebACL = module.web.web_acl_name, Rule = "ALL", Region = local.region }
        threshold   = 100
      }
      unhealthy-targets = {
        description = "ALB has unhealthy app targets"
        namespace   = "AWS/ApplicationELB"
        metric      = "UnHealthyHostCount"
        dimensions  = { LoadBalancer = module.web.alb_arn_suffix, TargetGroup = module.web.target_group_arn_suffix }
        threshold   = 0
      }
    },
    var.enable_network_firewall ? {
      firewall-blocked = {
        description = "Network Firewall dropped traffic (egress to a non-allowlisted destination or threat signature)"
        namespace   = "SecureVPC/${local.name}"
        metric      = "FirewallBlocked"
        dimensions  = {}
        threshold   = 0
      }
    } : {},
    var.enable_dns_firewall ? {
      dns-blocked = {
        description = "DNS Firewall blocked a query (threat list or non-allowlisted domain)"
        namespace   = "SecureVPC/${local.name}"
        metric      = "DnsFirewallBlocked"
        dimensions  = {}
        threshold   = 0
      }
    } : {},
  )
}

resource "aws_cloudwatch_metric_alarm" "this" {
  for_each = local.alarms

  alarm_name          = "${local.name}-${each.key}"
  alarm_description   = each.value.description
  namespace           = each.value.namespace
  metric_name         = each.value.metric
  dimensions          = each.value.dimensions
  statistic           = each.key == "unhealthy-targets" ? "Maximum" : "Sum"
  period              = 300
  evaluation_periods  = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = each.value.threshold
  treat_missing_data  = "notBreaching"
  alarm_actions       = [aws_sns_topic.alerts.arn]
  ok_actions          = [aws_sns_topic.alerts.arn]

  depends_on = [aws_cloudwatch_log_metric_filter.firewall_blocked, aws_cloudwatch_log_metric_filter.dns_blocked]
}
