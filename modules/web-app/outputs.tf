# modules/web-app/outputs.tf
#
# The IDs the labs' break.sh scripts target. Keep names stable.

output "alb_dns_name" {
  description = "Public DNS of the ALB — hit this in a browser / curl to see the app."
  value       = aws_lb.app.dns_name
}

output "alb_arn" {
  description = "ALB ARN."
  value       = aws_lb.app.arn
}

output "target_group_arn" {
  description = "Target group ARN (labs 7/8 inspect target health here)."
  value       = aws_lb_target_group.app.arn
}

output "asg_name" {
  description = "Auto Scaling group name (labs 4/8 mutate desired capacity / health)."
  value       = aws_autoscaling_group.app.name
}

output "launch_template_id" {
  description = "Launch template id."
  value       = aws_launch_template.app.id
}

output "instance_role_name" {
  description = "EC2 instance role name (lab 5 IAM lab detaches/attaches policies here)."
  value       = aws_iam_role.instance.name
}

output "db_instance_id" {
  description = <<-EOT
    RDS DB instance identifier (the name to pass to --db-instance-identifier),
    or null when create_database = false. Deliberately reads .identifier, not
    .id -- on the AWS provider version this repo pins (v6.x), .id returns the
    internal DbiResourceId (e.g. "db-XXXXXXXX...") instead of the identifier,
    which breaks every "aws rds describe-db-instances --db-instance-identifier
    $DB_ID" call in the labs with DBInstanceNotFound (confirmed by hand).
  EOT
  value       = try(aws_db_instance.db[0].identifier, null)
}

output "db_endpoint" {
  description = "RDS endpoint address, or null when create_database = false."
  value       = try(aws_db_instance.db[0].address, null)
}
