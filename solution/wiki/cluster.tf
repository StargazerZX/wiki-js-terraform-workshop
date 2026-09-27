# An ECS cluster is just a named grouping for services; with Fargate there are
# no servers in it to manage.

# 🏭 Production note: turn Container Insights on for real services (it's
# billed per metric, so it's off for a two-hour lab).
#trivy:ignore:AVD-AWS-0034
resource "aws_ecs_cluster" "this" {
  name = "${local.name}-cluster"

  setting {
    name  = "containerInsights"
    value = "disabled"
  }
}
