# modules/base-network/outputs.tf
#
# These outputs are the "contract" the web-app module and the labs' break.sh
# scripts consume. Keep the names stable — break.sh scripts grep for them.

output "vpc_id" {
  description = "VPC id."
  value       = aws_vpc.this.id
}

output "public_subnet_ids" {
  description = "Public subnet ids (ALB lives here)."
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet ids (app + db live here)."
  value       = aws_subnet.private[*].id
}

output "alb_security_group_id" {
  description = "SG for the ALB (public 80/443)."
  value       = aws_security_group.alb.id
}

output "app_security_group_id" {
  description = "SG for the app tier (80 from ALB only)."
  value       = aws_security_group.app.id
}

output "db_security_group_id" {
  description = "SG for the DB tier (3306 from app only)."
  value       = aws_security_group.db.id
}

output "nat_gateway_id" {
  description = "NAT Gateway id, or null when disabled."
  value       = try(aws_nat_gateway.this[0].id, null)
}

output "private_route_table_id" {
  description = "Private route table id (labs 4/6 mutate its default route)."
  value       = aws_route_table.private.id
}
