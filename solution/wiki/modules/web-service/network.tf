# internet --80--> [ALB SG] --container_port--> [service SG] --443--> internet
#
# The service accepts traffic ONLY from its own load balancer, and by default
# may only call out on 443 (to pull its image, write logs, read secrets).

resource "aws_security_group" "alb" {
  name        = "${var.name}-alb"
  description = "Load balancer for ${var.name}"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-alb" })
}

resource "aws_security_group" "service" {
  name        = "${var.name}-service"
  description = "Tasks of ${var.name}"
  vpc_id      = var.vpc_id
  tags        = merge(var.tags, { Name = "${var.name}-service" })
}

# A public website: the load balancer accepts the whole internet on port 80.
#trivy:ignore:AVD-AWS-0107
resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTP from the internet"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_egress_rule" "alb_to_service" {
  security_group_id            = aws_security_group.alb.id
  description                  = "To the tasks, on the container port"
  referenced_security_group_id = aws_security_group.service.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "service_from_alb" {
  security_group_id            = aws_security_group.service.id
  description                  = "From this service's load balancer only"
  referenced_security_group_id = aws_security_group.alb.id
  from_port                    = var.container_port
  to_port                      = var.container_port
  ip_protocol                  = "tcp"
}

# 🏭 Production note: with private subnets and VPC endpoints for ECR, Logs and
# Secrets Manager, this rule could point at the endpoints instead of the
# internet.
#trivy:ignore:AVD-AWS-0104
resource "aws_vpc_security_group_egress_rule" "service_https" {
  security_group_id = aws_security_group.service.id
  description       = "HTTPS out: image pull, logs, secrets"
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

# 🏭 Production note: a public ALB is the point of a website. What production
# adds is HTTPS (an ACM certificate on a 443 listener) and a WAF in front.
#trivy:ignore:AVD-AWS-0053
resource "aws_lb" "this" {
  name                       = "${var.name}-alb"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.subnet_ids
  drop_invalid_header_fields = true
  tags                       = var.tags
}

resource "aws_lb_target_group" "this" {
  name                 = "${var.name}-tg"
  port                 = var.container_port
  protocol             = "HTTP"
  target_type          = "ip" # Fargate tasks register by IP address
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 15
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }

  tags = var.tags
}

# 🏭 Production note: no domain name and no certificate in a classroom, so
# plain HTTP. Production listens on 443 and redirects 80 to it.
#trivy:ignore:AVD-AWS-0054
resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.this.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.this.arn
  }

  tags = var.tags
}
