variable "aws_region" {
  description = "Region for the workshop. Everything else in the workshop assumes this region."
  type        = string
  default     = "us-east-1"
}

variable "vpc_cidr" {
  description = "CIDR block for the workshop VPC. A /16 leaves plenty of room for 15+ students' load balancers, tasks and databases."
  type        = string
  default     = "10.20.0.0/16"
}
