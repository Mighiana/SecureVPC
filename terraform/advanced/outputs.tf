output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}

output "availability_zones" {
  description = "AZs every tier is spread across."
  value       = local.azs
}

output "subnet_ids" {
  description = "Subnet IDs per tier, keyed by AZ."
  value       = module.network.subnet_ids
}

output "subnet_cidrs" {
  description = "Subnet CIDRs per tier, keyed by AZ."
  value       = module.network.subnet_cidrs
}

output "nat_public_ips" {
  description = "Public IPs all allowlisted egress appears from (empty when egress_allowed_domains is empty)."
  value       = module.network.nat_public_ips
}

output "igw_id" {
  description = "Internet Gateway ID (source for Reachability Analyzer paths)."
  value       = module.network.igw_id
}

output "web_url" {
  description = "Public URL of the web tier (via WAF + ALB). Expect <h1>Secure Web Server</h1>."
  value       = module.web.web_url
}

output "asg_name" {
  description = "Auto Scaling group of the private app instances."
  value       = module.web.asg_name
}

output "web_acl_name" {
  description = "WAF web ACL protecting the ALB."
  value       = module.web.web_acl_name
}

output "network_firewall" {
  description = "Network Firewall name and per-AZ endpoint IDs (null when disabled)."
  value = var.enable_network_firewall ? {
    name         = module.firewall[0].firewall_name
    endpoint_ids = module.firewall[0].endpoint_ids
  } : null
}

output "vpc_endpoints" {
  description = "Interface endpoint IDs and the S3 gateway endpoint ID."
  value = {
    interface = module.endpoints.interface_endpoint_ids
    s3        = module.endpoints.s3_endpoint_id
  }
}

output "log_groups" {
  description = "Every CloudWatch log group this profile writes to."
  value = {
    vpc_flow_logs  = module.flow_logs.log_group_name
    firewall_alert = var.enable_network_firewall ? module.firewall[0].alert_log_group_name : null
    firewall_flow  = var.enable_network_firewall ? module.firewall[0].flow_log_group_name : null
    dns_queries    = var.enable_dns_firewall ? module.dns_firewall[0].query_log_group_name : null
    waf            = module.web.waf_log_group_name
    ssm_sessions   = module.web.session_log_group_name
  }
}

output "flow_log_archive" {
  description = "S3 archive of enhanced flow logs and the Athena objects that query it."
  value = {
    bucket        = module.flow_logs.s3_bucket_name
    database      = module.analytics.database_name
    table         = module.analytics.table_name
    workgroup     = module.analytics.workgroup_name
    named_queries = module.analytics.named_queries
  }
}

output "alerts_topic_arn" {
  description = "SNS topic receiving security alarms."
  value       = aws_sns_topic.alerts.arn
}

output "alarm_names" {
  description = "CloudWatch alarms wired to the SNS topic."
  value       = [for a in aws_cloudwatch_metric_alarm.this : a.alarm_name]
}

output "session_document_name" {
  description = "SSM session document that enforces encrypted, logged sessions."
  value       = module.web.session_document_name
}

output "start_session_command" {
  description = "Open a shell on one app instance through Session Manager (no SSH, no public IP)."
  value       = "aws ssm start-session --region ${local.region} --document-name ${module.web.session_document_name} --target $(aws autoscaling describe-auto-scaling-groups --region ${local.region} --auto-scaling-group-names ${module.web.asg_name} --query 'AutoScalingGroups[0].Instances[0].InstanceId' --output text)"
}

output "operator_policy_json" {
  description = "Least-privilege IAM policy for operators who need Session Manager access."
  value       = module.web.operator_policy_json
}

output "kms_key_arn" {
  description = "KMS key for this profile's logs, firewall, SNS and sessions."
  value       = aws_kms_key.this.arn
}

output "region" {
  description = "Region the profile is deployed in."
  value       = local.region
}

output "alb_arn" {
  description = "ALB ARN (used by verify-advanced.sh to confirm the WAF association)."
  value       = module.web.alb_arn
}
