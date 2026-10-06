output "alb_dns_name" {
  description = "Public DNS name of the ALB."
  value       = aws_lb.this.dns_name
}

output "alb_arn_suffix" {
  description = "ALB ARN suffix (CloudWatch dimension)."
  value       = aws_lb.this.arn_suffix
}

output "target_group_arn_suffix" {
  description = "Target group ARN suffix (CloudWatch dimension)."
  value       = aws_lb_target_group.app.arn_suffix
}

output "web_url" {
  description = "URL of the web tier."
  value       = var.certificate_arn == null ? "http://${aws_lb.this.dns_name}" : "https://${coalesce(var.web_hostname, aws_lb.this.dns_name)}"
}

output "asg_name" {
  description = "Auto Scaling group name."
  value       = aws_autoscaling_group.app.name
}

output "launch_template" {
  description = "Launch template ID and the hardening settings it enforces."
  value = {
    id               = aws_launch_template.app.id
    imdsv2_required  = aws_launch_template.app.metadata_options[0].http_tokens == "required"
    key_pair         = aws_launch_template.app.key_name
    root_encrypted   = aws_launch_template.app.block_device_mappings[0].ebs[0].encrypted
    instance_profile = aws_iam_instance_profile.app.name
  }
}

output "web_acl_name" {
  description = "WAF web ACL name."
  value       = aws_wafv2_web_acl.this.name
}

output "waf_log_group_name" {
  description = "CloudWatch log group with WAF logs."
  value       = aws_cloudwatch_log_group.waf.name
}

output "session_document_name" {
  description = "SSM session preferences document (pass with --document-name)."
  value       = aws_ssm_document.session.name
}

output "session_log_group_name" {
  description = "CloudWatch log group with Session Manager transcripts."
  value       = aws_cloudwatch_log_group.sessions.name
}

output "alb_logs_bucket" {
  description = "S3 bucket with ALB access logs."
  value       = aws_s3_bucket.alb_logs.bucket
}

output "operator_policy_json" {
  description = "Least-privilege IAM policy for human operators (attach to your own role)."
  value       = data.aws_iam_policy_document.operator.json
}

output "alb_arn" {
  description = "ALB ARN."
  value       = aws_lb.this.arn
}
