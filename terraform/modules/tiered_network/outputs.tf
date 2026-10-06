output "vpc_id" {
  description = "VPC ID."
  value       = aws_vpc.this.id
}

output "vpc_cidr" {
  description = "VPC CIDR."
  value       = aws_vpc.this.cidr_block
}

output "igw_id" {
  description = "Internet Gateway ID."
  value       = aws_internet_gateway.this.id
}

output "subnet_ids" {
  description = "Subnet IDs per tier, keyed by AZ."
  value = {
    firewall  = { for az, s in aws_subnet.firewall : az => s.id }
    public    = { for az, s in aws_subnet.public : az => s.id }
    app       = { for az, s in aws_subnet.app : az => s.id }
    endpoints = { for az, s in aws_subnet.endpoint : az => s.id }
    data      = { for az, s in aws_subnet.data : az => s.id }
  }
}

output "subnet_cidrs" {
  description = "Subnet CIDRs per tier, keyed by AZ."
  value = {
    firewall  = var.enable_firewall_subnets ? local.firewall_cidrs : {}
    public    = local.public_cidrs
    app       = local.app_cidrs
    endpoints = local.endpoint_cidrs
    data      = local.data_cidrs
  }
}

output "public_route_table_ids" {
  description = "Public route table IDs keyed by AZ."
  value       = { for az, rt in aws_route_table.public : az => rt.id }
}

output "app_route_table_ids" {
  description = "App-tier route table IDs keyed by AZ."
  value       = { for az, rt in aws_route_table.app : az => rt.id }
}

output "firewall_route_table_id" {
  description = "Route table shared by the firewall subnets (null without the firewall)."
  value       = var.enable_firewall_subnets ? aws_route_table.firewall[0].id : null
}

output "isolated_route_table_ids" {
  description = "Route tables with no route out of the VPC (endpoints and data tiers)."
  value       = { endpoints = aws_route_table.endpoint.id, data = aws_route_table.data.id }
}

output "nat_gateway_ids" {
  description = "NAT Gateway IDs keyed by AZ."
  value       = { for az, n in aws_nat_gateway.this : az => n.id }
}

output "nat_public_ips" {
  description = "NAT Gateway public IPs keyed by AZ (all app-tier egress appears from these)."
  value       = { for az, e in aws_eip.nat : az => e.public_ip }
}

output "nacl_ids" {
  description = "Network ACL IDs per tier."
  value = {
    firewall  = var.enable_firewall_subnets ? aws_network_acl.firewall[0].id : null
    public    = aws_network_acl.public.id
    app       = aws_network_acl.app.id
    endpoints = aws_network_acl.endpoint.id
    data      = aws_network_acl.data.id
  }
}
