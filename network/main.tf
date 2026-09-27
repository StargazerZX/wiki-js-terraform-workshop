# The workshop network: created ONCE, before class, and then only ever READ by
# the students' Terraform (via data sources, by tag).
#
#   🅢 Shared account: the presenter applies this once. All students share it.
#   🅿 Personal account: each student applies it once in their own account
#      (about a minute, and nothing in it is billed by the hour).
#
# Two public subnets (load balancer + Wiki.js tasks) and two private subnets
# (the database), across two availability zones — the minimum an ALB and an
# RDS subnet group accept.
#
# 🏭 Production note: production would run the tasks in the PRIVATE subnets and
# give them outbound access through a NAT gateway (~$33/month each) or VPC
# endpoints. Here the tasks sit in public subnets with a public IP so they can
# pull their image from ghcr.io without a NAT gateway. Their security group
# still only accepts traffic from their own load balancer.

data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 2)
}

# 🏭 Production note: enable VPC flow logs (to CloudWatch or S3) on any VPC
# that carries real traffic. Skipped for a one-day classroom network.
#trivy:ignore:AVD-AWS-0178
resource "aws_vpc" "workshop" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "ws-workshop-vpc"
  }
}

resource "aws_internet_gateway" "workshop" {
  vpc_id = aws_vpc.workshop.id

  tags = {
    Name = "ws-workshop-igw"
  }
}

# Public subnets auto-assign public IPs so Fargate tasks can reach ghcr.io
# without a NAT gateway (see the production note at the top).
#trivy:ignore:AVD-AWS-0164
resource "aws_subnet" "public" {
  count = length(local.azs)

  vpc_id                  = aws_vpc.workshop.id
  cidr_block              = cidrsubnet(var.vpc_cidr, 4, count.index)
  availability_zone       = local.azs[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name = "ws-workshop-public-${local.azs[count.index]}"
    Tier = "public"
  }
}

resource "aws_subnet" "private" {
  count = length(local.azs)

  vpc_id            = aws_vpc.workshop.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + 8)
  availability_zone = local.azs[count.index]

  tags = {
    Name = "ws-workshop-private-${local.azs[count.index]}"
    Tier = "private"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.workshop.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.workshop.id
  }

  tags = {
    Name = "ws-workshop-public"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Private subnets get the VPC's main route table: local traffic only, no
# internet route at all. The databases never need one.
