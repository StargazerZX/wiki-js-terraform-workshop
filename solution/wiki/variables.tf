variable "aws_region" {
  description = "Must match the region the workshop network was created in."
  type        = string
  default     = "us-east-1"
}

variable "student" {
  description = "Your short handle, e.g. \"alice\". Every resource name starts with ws-<student>, so it must be unique in the class."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,11}$", var.student))
    error_message = "student must be 2-12 characters: lowercase letters and digits, starting with a letter."
  }
}

variable "role_permissions_boundary_arn" {
  description = <<-EOT
    🅿 Own AWS account: leave empty.
    🅢 Shared workshop user: set it to the ARN your presenter gives you. The
    shared user may only create IAM roles that carry this boundary.
  EOT
  type        = string
  default     = ""
}

variable "wiki_image" {
  description = "Wiki.js container image. Pinned to an exact release so every student runs the same thing."
  type        = string
  default     = "ghcr.io/requarks/wiki:2.5.314"
}

variable "db_instance_class" {
  description = "RDS instance size. db.t4g.micro is free-tier eligible."
  type        = string
  default     = "db.t4g.micro"
}
