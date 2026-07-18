# envs/sandbox/outputs.tf
#
# These are the names the labs' break.sh scripts and READMEs read via
#   terraform -chdir=../../envs/sandbox output -raw <name>
# Keep them stable.

output "app_url" {
  description = "Open this in a browser / curl it to see NorthBank banking."
  value       = "http://${module.app.alb_dns_name}"
}

output "alb_dns_name" {
  value = module.app.alb_dns_name
}

output "alb_arn" {
  value = module.app.alb_arn
}

output "target_group_arn" {
  value = module.app.target_group_arn
}

output "asg_name" {
  value = module.app.asg_name
}

output "instance_role_name" {
  value = module.app.instance_role_name
}

output "vpc_id" {
  value = module.network.vpc_id
}

output "app_security_group_id" {
  value = module.network.app_security_group_id
}

output "alb_security_group_id" {
  value = module.network.alb_security_group_id
}

output "db_security_group_id" {
  value = module.network.db_security_group_id
}

output "private_route_table_id" {
  value = module.network.private_route_table_id
}

output "db_instance_id" {
  description = "RDS id, or null when create_database = false."
  value       = module.app.db_instance_id
}

output "db_endpoint" {
  description = "RDS endpoint, or null when create_database = false."
  value       = module.app.db_endpoint
}
