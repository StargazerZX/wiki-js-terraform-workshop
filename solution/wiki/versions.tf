terraform {
  # Any 1.10+ release works for everything in this workshop; it was written
  # against 1.16.1.
  required_version = ">= 1.10.0, < 2.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.58"
    }
  }

  # Local state, on purpose: one person, one laptop, two hours.
  # 🏭 Production note: remote state in S3 with native locking
  # (`use_lockfile = true`), so a team and its CI share one locked copy.
}

provider "aws" {
  region = var.aws_region

  default_tags {
    tags = {
      Workshop  = "terraform-wikijs"
      Owner     = var.student
      ManagedBy = "terraform"
    }
  }
}
