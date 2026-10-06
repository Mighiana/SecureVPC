# Five tiers per AZ, all carved from one /16:
#   firewall  10.0.0.0/28, 10.0.0.16/28   Network Firewall endpoints
#   public    10.0.1.0/24, 10.0.2.0/24    ALB + NAT Gateway (no instances)
#   app       10.0.11.0/24, 10.0.12.0/24  web servers, no public IPs
#   endpoints 10.0.21.0/24, 10.0.22.0/24  interface VPC endpoints
#   data      10.0.31.0/24, 10.0.32.0/24  no route out of the VPC at all

locals {
  az_index = { for i, az in var.azs : az => i }

  firewall_cidrs = { for az, i in local.az_index : az => cidrsubnet(var.vpc_cidr, 12, i) }
  public_cidrs   = { for az, i in local.az_index : az => cidrsubnet(var.vpc_cidr, 8, 1 + i) }
  app_cidrs      = { for az, i in local.az_index : az => cidrsubnet(var.vpc_cidr, 8, 11 + i) }
  endpoint_cidrs = { for az, i in local.az_index : az => cidrsubnet(var.vpc_cidr, 8, 21 + i) }
  data_cidrs     = { for az, i in local.az_index : az => cidrsubnet(var.vpc_cidr, 8, 31 + i) }

  nat_azs = var.enable_nat_gateway ? (var.single_nat_gateway ? [var.azs[0]] : var.azs) : []
}

resource "aws_vpc" "this" {
  #checkov:skip=CKV2_AWS_11:Flow logs are attached in the flow_logs module; checkov does not follow the cross-module reference.
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${var.name}-vpc" }
}

resource "aws_default_security_group" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-default-sg-locked" }
}

resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-igw" }
}

# ---------------------------------------------------------------------------
# Subnets
# ---------------------------------------------------------------------------

resource "aws_subnet" "firewall" {
  for_each = var.enable_firewall_subnets ? local.firewall_cidrs : {}

  vpc_id            = aws_vpc.this.id
  cidr_block        = each.value
  availability_zone = each.key

  tags = { Name = "${var.name}-firewall-${each.key}", Tier = "firewall" }
}

resource "aws_subnet" "public" {
  for_each = local.public_cidrs

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = { Name = "${var.name}-public-${each.key}", Tier = "public" }
}

resource "aws_subnet" "app" {
  for_each = local.app_cidrs

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = { Name = "${var.name}-app-${each.key}", Tier = "app" }
}

resource "aws_subnet" "endpoint" {
  for_each = local.endpoint_cidrs

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = { Name = "${var.name}-endpoints-${each.key}", Tier = "endpoints" }
}

resource "aws_subnet" "data" {
  for_each = local.data_cidrs

  vpc_id                  = aws_vpc.this.id
  cidr_block              = each.value
  availability_zone       = each.key
  map_public_ip_on_launch = false

  tags = { Name = "${var.name}-data-${each.key}", Tier = "data" }
}

# ---------------------------------------------------------------------------
# NAT Gateways (app tier egress; the firewall decides what actually leaves)
# ---------------------------------------------------------------------------

resource "aws_eip" "nat" {
  for_each = toset(local.nat_azs)

  domain = "vpc"

  tags = { Name = "${var.name}-nat-eip-${each.key}" }

  depends_on = [aws_internet_gateway.this]
}

resource "aws_nat_gateway" "this" {
  for_each = toset(local.nat_azs)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.public[each.key].id

  tags = { Name = "${var.name}-nat-${each.key}" }

  depends_on = [aws_internet_gateway.this]
}

# ---------------------------------------------------------------------------
# Route tables
# ---------------------------------------------------------------------------

# Firewall subnets: the network_firewall module adds 0.0.0.0/0 -> IGW.
resource "aws_route_table" "firewall" {
  count = var.enable_firewall_subnets ? 1 : 0

  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-firewall-rt" }
}

resource "aws_route_table_association" "firewall" {
  for_each = aws_subnet.firewall

  subnet_id      = each.value.id
  route_table_id = aws_route_table.firewall[0].id
}

# One public route table per AZ so each AZ can point at its own firewall endpoint.
resource "aws_route_table" "public" {
  for_each = local.public_cidrs

  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-public-rt-${each.key}" }
}

# Without the firewall, public subnets route straight to the IGW.
resource "aws_route" "public_internet" {
  for_each = var.enable_firewall_subnets ? {} : local.public_cidrs

  route_table_id         = aws_route_table.public[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public[each.key].id
}

resource "aws_route_table" "app" {
  for_each = local.app_cidrs

  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-app-rt-${each.key}" }
}

resource "aws_route" "app_nat" {
  for_each = var.enable_nat_gateway ? local.app_cidrs : {}

  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[var.single_nat_gateway ? var.azs[0] : each.key].id
}

resource "aws_route_table_association" "app" {
  for_each = aws_subnet.app

  subnet_id      = each.value.id
  route_table_id = aws_route_table.app[each.key].id
}

# Endpoint and data tiers: local route only. Nothing here can reach the internet.
resource "aws_route_table" "endpoint" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-endpoints-rt" }
}

resource "aws_route_table_association" "endpoint" {
  for_each = aws_subnet.endpoint

  subnet_id      = each.value.id
  route_table_id = aws_route_table.endpoint.id
}

resource "aws_route_table" "data" {
  vpc_id = aws_vpc.this.id

  tags = { Name = "${var.name}-data-rt" }
}

resource "aws_route_table_association" "data" {
  for_each = aws_subnet.data

  subnet_id      = each.value.id
  route_table_id = aws_route_table.data.id
}
