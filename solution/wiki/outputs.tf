output "wiki_url" {
  description = "Open this in a browser."
  value       = module.wiki.url
}

output "cluster_name" {
  value = aws_ecs_cluster.this.name
}

output "service_name" {
  value = module.wiki.service_name
}

output "log_group_name" {
  value = module.wiki.log_group_name
}
