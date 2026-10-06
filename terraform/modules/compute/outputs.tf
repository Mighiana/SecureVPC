output "bastion_instance_id" {
  description = "Instance ID of the bastion host."
  value       = aws_instance.bastion.id
}

output "bastion_public_ip" {
  description = "Public IPv4 address of the bastion host."
  value       = aws_instance.bastion.public_ip
}

output "bastion_private_ip" {
  description = "Private IPv4 address of the bastion host."
  value       = aws_instance.bastion.private_ip
}

output "web_instance_id" {
  description = "Instance ID of the private web server."
  value       = aws_instance.web.id
}

output "web_private_ip" {
  description = "Private IPv4 address of the web server."
  value       = aws_instance.web.private_ip
}

output "web_public_ip" {
  description = "Public IPv4 of the web server. Expected to be empty."
  value       = aws_instance.web.public_ip
}

output "key_pair_name" {
  description = "Name of the EC2 key pair created from the supplied public key."
  value       = aws_key_pair.admin.key_name
}
