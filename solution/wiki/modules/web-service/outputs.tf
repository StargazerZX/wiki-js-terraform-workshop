output "url" {
  description = "Where the service answers."
  value       = "http://${aws_lb.this.dns_name}"
}

output "service_security_group_id" {
  description = "Security group of the tasks. Add rules to it for anything the service must reach (e.g. a database)."
  value       = aws_security_group.service.id
}

output "service_name" {
  description = "ECS service name."
  value       = aws_ecs_service.this.name
}

output "log_group_name" {
  description = "CloudWatch log group with the container logs."
  value       = aws_cloudwatch_log_group.this.name
}
