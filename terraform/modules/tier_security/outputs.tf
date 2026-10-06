output "alb_sg_id" {
  description = "ALB security group ID."
  value       = aws_security_group.alb.id
}

output "app_sg_id" {
  description = "App tier security group ID."
  value       = aws_security_group.app.id
}

output "endpoints_sg_id" {
  description = "Interface endpoint security group ID."
  value       = aws_security_group.endpoints.id
}

output "data_sg_id" {
  description = "Data tier security group ID."
  value       = aws_security_group.data.id
}
