# ---- What the service is ----------------------------------------------------

variable "name" {
  description = "Name for every resource this module creates, e.g. \"ws-alice-wiki\"."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9-]{1,28}$", var.name))
    error_message = "name must be 1-28 lowercase letters, digits or hyphens (load balancer and target group names are capped at 32, and we append a suffix)."
  }
}

variable "image" {
  description = "Container image, including the tag."
  type        = string
}

variable "container_port" {
  description = "Port the application listens on inside the container."
  type        = number
}

variable "tier" {
  description = "Size preset: small (0.25 vCPU / 0.5 GB), medium (0.5 vCPU / 1 GB) or large (1 vCPU / 2 GB)."
  type        = string
  default     = "small"

  validation {
    condition     = contains(["small", "medium", "large"], var.tier)
    error_message = "tier must be one of: small, medium, large."
  }
}

variable "desired_count" {
  description = "How many copies of the container to run."
  type        = number
  default     = 1
}

variable "environment" {
  description = "Plain environment variables, as NAME => value. Never secrets: these are visible in the task definition."
  type        = map(string)
  default     = {}
}

variable "secrets" {
  description = "Secret environment variables, as NAME => { secret_arn, json_key }. ECS reads them from Secrets Manager when the container starts."
  type = map(object({
    secret_arn = string
    json_key   = optional(string)
  }))
  default = {}
}

variable "health_check_path" {
  description = "Path the load balancer calls to decide whether a container is healthy."
  type        = string
  default     = "/"
}

variable "health_check_grace_period_seconds" {
  description = "How long ECS ignores failed health checks after a container starts. Raise it for slow-starting apps."
  type        = number
  default     = 60
}

variable "tags" {
  description = "Extra tags for every resource this module creates."
  type        = map(string)
  default     = {}
}

# ---- Where it runs ------------------------------------------------------------

variable "cluster_arn" {
  description = "ECS cluster to run the service in."
  type        = string
}

variable "vpc_id" {
  description = "VPC for the load balancer and the service."
  type        = string
}

variable "subnet_ids" {
  description = "Public subnets for the load balancer and the tasks. At least two, in different availability zones."
  type        = list(string)

  validation {
    condition     = length(var.subnet_ids) >= 2
    error_message = "An Application Load Balancer needs at least two subnets."
  }
}

variable "role_permissions_boundary_arn" {
  description = "Permissions boundary for the task execution role. Empty means none."
  type        = string
  default     = ""
}

variable "log_retention_days" {
  description = "How long CloudWatch keeps the container logs."
  type        = number
  default     = 7
}
