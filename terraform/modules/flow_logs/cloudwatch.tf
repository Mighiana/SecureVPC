locals {
  log_group_name = "/${var.name}/vpc-flow-logs"
}

resource "aws_cloudwatch_log_group" "flow_logs" {
  #checkov:skip=CKV_AWS_338:Retention is a variable; the short default keeps a lab cheap. Enable the S3 archive for longer retention.
  name              = local.log_group_name
  retention_in_days = var.retention_in_days
  kms_key_id        = var.enable_kms ? aws_kms_key.logs[0].arn : null

  tags = { Name = "${var.name}-vpc-flow-logs" }
}

resource "aws_iam_role" "flow_logs" {
  name_prefix = "${var.name}-flowlogs-"
  description = "Lets VPC Flow Logs write to the ${local.log_group_name} log group"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "vpc-flow-logs.amazonaws.com" }
      Action    = "sts:AssumeRole"
      Condition = {
        StringEquals = { "aws:SourceAccount" = var.account_id }
        ArnLike      = { "aws:SourceArn" = "arn:${var.partition}:ec2:${var.region}:${var.account_id}:vpc-flow-log/*" }
      }
    }]
  })
}

resource "aws_iam_role_policy" "flow_logs" {
  name = "write-flow-logs"
  role = aws_iam_role.flow_logs.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
        "logs:DescribeLogGroups",
        "logs:DescribeLogStreams",
      ]
      Resource = [
        aws_cloudwatch_log_group.flow_logs.arn,
        "${aws_cloudwatch_log_group.flow_logs.arn}:*",
      ]
    }]
  })
}

resource "aws_flow_log" "cloudwatch" {
  vpc_id                   = var.vpc_id
  traffic_type             = var.traffic_type
  log_destination_type     = "cloud-watch-logs"
  log_destination          = aws_cloudwatch_log_group.flow_logs.arn
  iam_role_arn             = aws_iam_role.flow_logs.arn
  max_aggregation_interval = var.max_aggregation_interval

  tags = { Name = "${var.name}-flow-log-cloudwatch" }

  depends_on = [aws_iam_role_policy.flow_logs]
}

# ---------------------------------------------------------------------------
# Visibility: metric + saved Logs Insights queries (no alarms, no extra cost
# beyond the custom metric)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_metric_filter" "rejected" {
  name           = "${var.name}-rejected-flows"
  log_group_name = aws_cloudwatch_log_group.flow_logs.name
  pattern        = "[version, account, eni, source, destination, srcport, destport, protocol, packets, bytes, windowstart, windowend, action=\"REJECT\", flowlogstatus]"

  metric_transformation {
    name          = "RejectedFlows"
    namespace     = "SecureVPC/${var.name}"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_query_definition" "top_rejected_sources" {
  name            = "${var.name}/top-rejected-sources"
  log_group_names = [aws_cloudwatch_log_group.flow_logs.name]

  query_string = <<-EOT
    fields @timestamp, srcAddr, dstAddr, dstPort, protocol, action
    | filter action = "REJECT"
    | stats count(*) as rejected by srcAddr, dstPort
    | sort rejected desc
    | limit 25
  EOT
}

resource "aws_cloudwatch_query_definition" "ssh_attempts" {
  name            = "${var.name}/ssh-attempts"
  log_group_names = [aws_cloudwatch_log_group.flow_logs.name]

  query_string = <<-EOT
    fields @timestamp, srcAddr, dstAddr, action
    | filter dstPort = 22
    | stats count(*) as attempts by srcAddr, dstAddr, action
    | sort attempts desc
    | limit 50
  EOT
}

resource "aws_cloudwatch_query_definition" "private_subnet_egress" {
  name            = "${var.name}/accepted-flows-by-destination-port"
  log_group_names = [aws_cloudwatch_log_group.flow_logs.name]

  query_string = <<-EOT
    fields @timestamp, srcAddr, dstAddr, dstPort, bytes
    | filter action = "ACCEPT"
    | stats sum(bytes) as totalBytes, count(*) as flows by dstPort
    | sort totalBytes desc
    | limit 25
  EOT
}
