# ---------------------------------------------------------------------------
# Network
# ---------------------------------------------------------------------------

output "region" {
  description = "Region the stack is deployed in."
  value       = data.aws_region.current.name
}

output "availability_zone" {
  description = "AZ hosting both subnets."
  value       = local.availability_zone
}

output "vpc_id" {
  description = "VPC ID."
  value       = module.network.vpc_id
}

output "vpc_cidr" {
  description = "VPC CIDR block."
  value       = module.network.vpc_cidr
}

output "public_subnet_id" {
  description = "Public subnet ID (bastion + NAT Gateway)."
  value       = module.network.public_subnet_id
}

output "private_subnet_id" {
  description = "Private subnet ID (web server)."
  value       = module.network.private_subnet_id
}

output "internet_gateway_id" {
  description = "Internet Gateway ID."
  value       = module.network.internet_gateway_id
}

output "nat_gateway_id" {
  description = "NAT Gateway ID."
  value       = module.network.nat_gateway_id
}

output "nat_public_ip" {
  description = "NAT Gateway Elastic IP. The web server's outbound traffic should appear from this address."
  value       = module.network.nat_public_ip
}

output "route_table_ids" {
  description = "Route tables by tier."
  value = {
    public  = module.network.public_route_table_id
    private = module.network.private_route_table_id
  }
}

output "network_acl_ids" {
  description = "Network ACLs by tier."
  value = {
    public  = module.network.public_nacl_id
    private = module.network.private_nacl_id
  }
}

output "security_group_ids" {
  description = "Security groups by role."
  value = {
    bastion = module.security.bastion_sg_id
    web     = module.security.web_sg_id
  }
}

# ---------------------------------------------------------------------------
# Compute
# ---------------------------------------------------------------------------

output "bastion_instance_id" {
  description = "Bastion EC2 instance ID."
  value       = module.compute.bastion_instance_id
}

output "bastion_public_ip" {
  description = "Bastion public IP (the only public entry point)."
  value       = module.compute.bastion_public_ip
}

output "web_instance_id" {
  description = "Private web server EC2 instance ID."
  value       = module.compute.web_instance_id
}

output "web_private_ip" {
  description = "Private web server IP (reachable only via the bastion)."
  value       = module.compute.web_private_ip
}

output "web_public_ip" {
  description = "Should be empty: the web server has no public IP."
  value       = module.compute.web_public_ip
}

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

output "flow_log_id" {
  description = "VPC Flow Log (CloudWatch destination) ID."
  value       = module.flow_logs.cloudwatch_flow_log_id
}

output "flow_log_group_name" {
  description = "CloudWatch log group receiving VPC Flow Logs."
  value       = module.flow_logs.log_group_name
}

output "flow_logs_kms_key_arn" {
  description = "KMS key encrypting flow logs (null when disabled)."
  value       = module.flow_logs.kms_key_arn
}

output "flow_logs_s3_bucket" {
  description = "S3 archive bucket for flow logs (null when disabled)."
  value       = module.flow_logs.s3_bucket_name
}

output "logs_insights_queries" {
  description = "Saved CloudWatch Logs Insights query names."
  value       = module.flow_logs.query_definition_names
}

# ---------------------------------------------------------------------------
# Validation helpers (contain no secrets)
# ---------------------------------------------------------------------------

output "ssh_bastion_command" {
  description = "SSH to the bastion. Replace the key path with your own private key."
  value       = "ssh -i ~/.ssh/securevpc ec2-user@${module.compute.bastion_public_ip}"
}

output "ssh_web_via_bastion_command" {
  description = "SSH to the private web server through the bastion (ProxyCommand -W; the private key never leaves your machine)."
  value       = "ssh -i ~/.ssh/securevpc -o ProxyCommand=\"ssh -i ~/.ssh/securevpc -W %h:%p ec2-user@${module.compute.bastion_public_ip}\" ec2-user@${module.compute.web_private_ip}"
}

output "curl_web_via_bastion_command" {
  description = "Fetch the private web page from the bastion."
  value       = "ssh -i ~/.ssh/securevpc ec2-user@${module.compute.bastion_public_ip} curl -s http://${module.compute.web_private_ip}/"
}

output "check_nat_egress_command" {
  description = "From the web server, print its public egress IP. It should equal nat_public_ip."
  value       = "ssh -i ~/.ssh/securevpc -o ProxyCommand=\"ssh -i ~/.ssh/securevpc -W %h:%p ec2-user@${module.compute.bastion_public_ip}\" ec2-user@${module.compute.web_private_ip} curl -s https://checkip.amazonaws.com"
}

output "tail_flow_logs_command" {
  description = "Stream recent flow log records with the AWS CLI."
  value       = "aws logs tail ${module.flow_logs.log_group_name} --since 15m --follow --region ${data.aws_region.current.name}"
}
