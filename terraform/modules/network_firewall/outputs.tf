output "firewall_arn" {
  description = "Network Firewall ARN."
  value       = aws_networkfirewall_firewall.this.arn
}

output "firewall_name" {
  description = "Network Firewall name."
  value       = aws_networkfirewall_firewall.this.name
}

output "endpoint_ids" {
  description = "Firewall endpoint (VPC endpoint) IDs keyed by AZ."
  value       = local.endpoint_ids
}

output "policy_arn" {
  description = "Firewall policy ARN."
  value       = aws_networkfirewall_firewall_policy.this.arn
}

output "rules" {
  description = "Rendered Suricata rules of the custom segmentation rule group, in evaluation order."
  value       = local.rules
}

output "alert_log_group_name" {
  description = "CloudWatch log group with firewall ALERT logs."
  value       = aws_cloudwatch_log_group.alert.name
}

output "flow_log_group_name" {
  description = "CloudWatch log group with firewall FLOW logs."
  value       = aws_cloudwatch_log_group.flow.name
}

output "igw_edge_route_table_id" {
  description = "Route table associated with the Internet Gateway (ingress routing)."
  value       = aws_route_table.igw_edge.id
}
