output "rule_group_id" {
  description = "DNS Firewall rule group ID."
  value       = aws_route53_resolver_firewall_rule_group.this.id
}

output "allowed_domains" {
  description = "Rendered allowlist (each domain plus its wildcard)."
  value       = local.allowed
}

output "query_log_group_name" {
  description = "CloudWatch log group with Resolver query logs."
  value       = aws_cloudwatch_log_group.queries.name
}
