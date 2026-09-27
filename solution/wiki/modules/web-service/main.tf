data "aws_region" "current" {}

locals {
  # Callers pick a size, not raw numbers. Every pair here is a valid Fargate
  # CPU/memory combination, so a caller can't ask for one that isn't.
  tiers = {
    small  = { cpu = 256, memory = 512 }
    medium = { cpu = 512, memory = 1024 }
    large  = { cpu = 1024, memory = 2048 }
  }
  size = local.tiers[var.tier]

  # Maps in the interface, lists for ECS. A `for` over a map runs in sorted
  # key order, so the task definition (and the plan) is stable.
  container_environment = [
    for name, value in var.environment : { name = name, value = value }
  ]

  # ECS syntax for "one JSON key of a secret" is <secret-arn>:<json-key>::
  # The module knows that syntax so callers don't have to.
  container_secrets = [
    for name, secret in var.secrets : {
      name      = name
      valueFrom = secret.json_key == null ? secret.secret_arn : "${secret.secret_arn}:${secret.json_key}::"
    }
  ]

  # Several env vars can come from one secret; IAM needs each secret once.
  secret_arns = distinct([for secret in values(var.secrets) : secret.secret_arn])
}

# 🏭 Production note: encrypt log groups with a customer-managed KMS key.
#trivy:ignore:AVD-AWS-0017
resource "aws_cloudwatch_log_group" "this" {
  name              = "/ecs/${var.name}"
  retention_in_days = var.log_retention_days
  tags              = var.tags
}

resource "aws_ecs_task_definition" "this" {
  family                   = var.name
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = local.size.cpu
  memory                   = local.size.memory
  execution_role_arn       = aws_iam_role.execution.arn

  runtime_platform {
    operating_system_family = "LINUX"
    cpu_architecture        = "X86_64"
  }

  container_definitions = jsonencode([
    {
      name         = "app"
      image        = var.image
      essential    = true
      portMappings = [{ containerPort = var.container_port, protocol = "tcp" }]
      environment  = local.container_environment
      secrets      = local.container_secrets

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.this.name
          "awslogs-region"        = data.aws_region.current.region
          "awslogs-stream-prefix" = "app"
        }
      }
    }
  ])

  tags = var.tags
}

resource "aws_ecs_service" "this" {
  name            = var.name
  cluster         = var.cluster_arn
  task_definition = aws_ecs_task_definition.this.arn
  desired_count   = var.desired_count
  launch_type     = "FARGATE"

  health_check_grace_period_seconds = var.health_check_grace_period_seconds

  network_configuration {
    subnets          = var.subnet_ids
    security_groups  = [aws_security_group.service.id]
    assign_public_ip = true # public subnets, no NAT gateway: needed to pull the image
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.this.arn
    container_name   = "app"
    container_port   = var.container_port
  }

  # The target group only accepts targets once the listener points at it, and
  # the first task can only start once its role may write logs and read secrets.
  depends_on = [aws_lb_listener.http, aws_iam_role_policy.execution]

  tags = var.tags
}
