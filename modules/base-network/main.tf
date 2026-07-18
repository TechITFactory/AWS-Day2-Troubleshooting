# modules/base-network/main.tf
#
# NorthBank's shared VPC foundation: a VPC with public + private subnets across
# two AZs, an Internet Gateway for the public tier, and a single NAT Gateway so
# private instances can reach the internet (patch downloads, SSM) outbound only.
#
# Cost note: ONE NAT Gateway (not one-per-AZ) keeps the lab bill low. That's a
# deliberate non-production trade-off — see README.md.

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  # Use the first two available AZs in the region.
  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  common_tags = merge({
    Project   = "NorthBank"
    Env       = var.environment
    ManagedBy = "terraform"
    Module    = "base-network"
  }, var.tags)
}

# ---------------------------------------------------------------------------
# VPC
# ---------------------------------------------------------------------------
resource "aws_vpc" "this" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(local.common_tags, { Name = "${var.name}-vpc" })
}

# ---------------------------------------------------------------------------
# Subnets — 2 public, 2 private
# ---------------------------------------------------------------------------
resource "aws_subnet" "public" {
  count                   = length(local.azs)
  vpc_id                  = aws_vpc.this.id
  availability_zone       = local.azs[count.index]
  cidr_block              = cidrsubnet(var.vpc_cidr, 8, count.index)       # /24s: .0, .1
  map_public_ip_on_launch = true

  tags = merge(local.common_tags, {
    Name = "${var.name}-public-${local.azs[count.index]}"
    Tier = "public"
  })
}

resource "aws_subnet" "private" {
  count             = length(local.azs)
  vpc_id            = aws_vpc.this.id
  availability_zone = local.azs[count.index]
  cidr_block        = cidrsubnet(var.vpc_cidr, 8, count.index + 10)        # /24s: .10, .11

  tags = merge(local.common_tags, {
    Name = "${var.name}-private-${local.azs[count.index]}"
    Tier = "private"
  })
}

# ---------------------------------------------------------------------------
# Internet Gateway + public routing
# ---------------------------------------------------------------------------
resource "aws_internet_gateway" "this" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "${var.name}-igw" })
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "${var.name}-public-rt" })
}

resource "aws_route" "public_internet" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.this.id
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# ---------------------------------------------------------------------------
# NAT Gateway (single, in the first public subnet) + private routing
# ---------------------------------------------------------------------------
resource "aws_eip" "nat" {
  count  = var.enable_nat_gateway ? 1 : 0
  domain = "vpc"
  tags   = merge(local.common_tags, { Name = "${var.name}-nat-eip" })
}

resource "aws_nat_gateway" "this" {
  count         = var.enable_nat_gateway ? 1 : 0
  allocation_id = aws_eip.nat[0].id
  subnet_id     = aws_subnet.public[0].id
  tags          = merge(local.common_tags, { Name = "${var.name}-nat" })

  depends_on = [aws_internet_gateway.this]
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.this.id
  tags   = merge(local.common_tags, { Name = "${var.name}-private-rt" })
}

# Only add the default route through NAT when NAT is enabled. Lab 6 (networking)
# and lab 4 (EC2) can toggle var.enable_nat_gateway off to simulate "private
# instances suddenly can't reach the internet."
resource "aws_route" "private_nat" {
  count                  = var.enable_nat_gateway ? 1 : 0
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.this[0].id
}

resource "aws_route_table_association" "private" {
  count          = length(aws_subnet.private)
  subnet_id      = aws_subnet.private[count.index].id
  route_table_id = aws_route_table.private.id
}

# ---------------------------------------------------------------------------
# Core security groups (referenced by the web-app module)
# ---------------------------------------------------------------------------

# ALB SG: open 80/443 from the internet.
resource "aws_security_group" "alb" {
  name        = "${var.name}-alb-sg"
  description = "NorthBank ALB - public HTTP/HTTPS"
  vpc_id      = aws_vpc.this.id
  tags        = merge(local.common_tags, { Name = "${var.name}-alb-sg" })
}

resource "aws_security_group_rule" "alb_http_in" {
  type              = "ingress"
  security_group_id = aws_security_group.alb.id
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "HTTP from internet"
}

resource "aws_security_group_rule" "alb_all_out" {
  type              = "egress"
  security_group_id = aws_security_group.alb.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "All outbound"
}

# App SG: HTTP only from the ALB SG (not the internet). This is the SG lab 6
# breaks by removing the ALB->app rule ("healthy targets go unhealthy").
resource "aws_security_group" "app" {
  name        = "${var.name}-app-sg"
  description = "NorthBank app tier - HTTP from ALB only"
  vpc_id      = aws_vpc.this.id
  tags        = merge(local.common_tags, { Name = "${var.name}-app-sg" })
}

resource "aws_security_group_rule" "app_http_from_alb" {
  type                     = "ingress"
  security_group_id        = aws_security_group.app.id
  from_port                = 80
  to_port                  = 80
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.alb.id
  description              = "HTTP from ALB"
}

resource "aws_security_group_rule" "app_all_out" {
  type              = "egress"
  security_group_id = aws_security_group.app.id
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  description       = "All outbound (patching, SSM, RDS)"
}

# DB SG: MySQL/Aurora port from the app SG only. Used by web-app's optional RDS.
resource "aws_security_group" "db" {
  name        = "${var.name}-db-sg"
  description = "NorthBank DB tier - 3306 from app only"
  vpc_id      = aws_vpc.this.id
  tags        = merge(local.common_tags, { Name = "${var.name}-db-sg" })
}

resource "aws_security_group_rule" "db_mysql_from_app" {
  type                     = "ingress"
  security_group_id        = aws_security_group.db.id
  from_port                = 3306
  to_port                  = 3306
  protocol                 = "tcp"
  source_security_group_id = aws_security_group.app.id
  description              = "MySQL from app tier"
}
