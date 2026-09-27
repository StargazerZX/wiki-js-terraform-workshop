# A module states the MINIMUM versions it works with. The root that calls it
# pins exact versions. No provider block: the module uses the caller's.
terraform {
  required_version = ">= 1.10.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }
}
