output "bastion_sg_id" {
  description = "ID of the bastion security group."
  value       = aws_security_group.bastion.id
}

output "web_sg_id" {
  description = "ID of the private web server security group."
  value       = aws_security_group.web.id
}
