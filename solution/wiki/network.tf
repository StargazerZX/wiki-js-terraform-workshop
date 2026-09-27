# The network already exists: it was created before class (network/ in this
# repo). This root only READS it, by tag. Data sources are how Terraform code
# uses infrastructure it doesn't own.

data "aws_vpc" "workshop" {
  tags = {
    Name = "ws-workshop-vpc"
  }
}

data "aws_subnets" "public" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.workshop.id]
  }

  tags = {
    Tier = "public"
  }
}

data "aws_subnets" "private" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.workshop.id]
  }

  tags = {
    Tier = "private"
  }
}

locals {
  # Every resource name starts with this, so 15 people can share one account.
  name = "ws-${var.student}"
}
