# The EXECUTION role is what ECS itself uses to start the container: write its
# logs, and read its secrets. (A separate TASK role would be what the app's own
# code uses to call AWS. Wiki.js doesn't call AWS, so there isn't one.)

data "aws_iam_policy_document" "assume_by_ecs_tasks" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "execution" {
  name                 = "${var.name}-exec"
  assume_role_policy   = data.aws_iam_policy_document.assume_by_ecs_tasks.json
  permissions_boundary = var.role_permissions_boundary_arn == "" ? null : var.role_permissions_boundary_arn
  tags                 = var.tags
}

data "aws_iam_policy_document" "execution" {
  statement {
    sid       = "WriteOwnLogs"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }

  # Only when the caller passed secrets: a statement with an empty resource
  # list is invalid, so this block exists zero or one times.
  dynamic "statement" {
    for_each = length(local.secret_arns) > 0 ? [1] : []

    content {
      sid       = "ReadOwnSecrets"
      actions   = ["secretsmanager:GetSecretValue"]
      resources = local.secret_arns
    }
  }
}

resource "aws_iam_role_policy" "execution" {
  name   = "${var.name}-exec"
  role   = aws_iam_role.execution.id
  policy = data.aws_iam_policy_document.execution.json
}
