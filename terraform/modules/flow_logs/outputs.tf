output "cloudwatch_flow_log_id" {
  description = "ID of the VPC Flow Log delivering to CloudWatch Logs."
  value       = aws_flow_log.cloudwatch.id
}

output "log_group_name" {
  description = "CloudWatch log group receiving VPC Flow Logs."
  value       = aws_cloudwatch_log_group.flow_logs.name
}

output "log_group_arn" {
  description = "ARN of the CloudWatch log group receiving VPC Flow Logs."
  value       = aws_cloudwatch_log_group.flow_logs.arn
}

output "flow_logs_role_arn" {
  description = "IAM role assumed by the VPC Flow Logs service."
  value       = aws_iam_role.flow_logs.arn
}

output "kms_key_arn" {
  description = "KMS key encrypting flow logs (null when disabled)."
  value       = var.enable_kms ? aws_kms_key.logs[0].arn : null
}

output "s3_flow_log_id" {
  description = "ID of the VPC Flow Log delivering to S3 (null when disabled)."
  value       = var.enable_s3_archive ? aws_flow_log.s3[0].id : null
}

output "s3_bucket_name" {
  description = "S3 bucket archiving flow logs (null when disabled)."
  value       = var.enable_s3_archive ? aws_s3_bucket.archive[0].bucket : null
}

output "rejected_flows_metric" {
  description = "Namespace/name of the custom metric counting REJECT flow records."
  value       = "SecureVPC/${var.name} RejectedFlows"
}

output "query_definition_names" {
  description = "Saved CloudWatch Logs Insights queries."
  value = [
    aws_cloudwatch_query_definition.top_rejected_sources.name,
    aws_cloudwatch_query_definition.ssh_attempts.name,
    aws_cloudwatch_query_definition.private_subnet_egress.name,
  ]
}
