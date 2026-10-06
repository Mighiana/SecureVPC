output "interface_endpoint_ids" {
  description = "Interface endpoint IDs keyed by service suffix."
  value       = { for k, e in aws_vpc_endpoint.interface : k => e.id }
}

output "s3_endpoint_id" {
  description = "S3 gateway endpoint ID."
  value       = aws_vpc_endpoint.s3.id
}

output "s3_endpoint_policy" {
  description = "Rendered S3 gateway endpoint policy (data perimeter)."
  value       = aws_vpc_endpoint.s3.policy
}
