# modules/web-app/variables.tf

variable "name" {
  description = "Name prefix (e.g. northbank-nonprod-web)."
  type        = string
  default     = "northbank-web"
}

variable "environment" {
  description = "Environment tag value."
  type        = string
  default     = "nonprod"
}

# ---- inputs from base-network -------------------------------------------
variable "vpc_id" {
  description = "VPC id (base-network.vpc_id)."
  type        = string
}

variable "public_subnet_ids" {
  description = "Public subnet ids for the ALB (base-network.public_subnet_ids)."
  type        = list(string)
}

variable "private_subnet_ids" {
  description = "Private subnet ids for the app + db (base-network.private_subnet_ids)."
  type        = list(string)
}

variable "alb_security_group_id" {
  description = "ALB SG (base-network.alb_security_group_id)."
  type        = string
}

variable "app_security_group_id" {
  description = "App SG (base-network.app_security_group_id)."
  type        = string
}

variable "db_security_group_id" {
  description = "DB SG (base-network.db_security_group_id)."
  type        = string
}

# ---- app tier -----------------------------------------------------------
variable "instance_type" {
  description = "EC2 instance type for the web tier. t3.micro keeps cost minimal."
  type        = string
  default     = "t3.micro"
}

variable "min_size" {
  type    = number
  default = 2
}

variable "max_size" {
  type    = number
  default = 4
}

variable "desired_capacity" {
  type    = number
  default = 2
}

variable "health_check_path" {
  description = "ALB target-group health check path (served by user-data.sh)."
  type        = string
  default     = "/health"
}

# ---- optional database (lab 9) ------------------------------------------
variable "create_database" {
  description = "Create an RDS MySQL instance. OFF by default to save cost; turn on for labs 9/11/15."
  type        = bool
  default     = false
}

variable "db_instance_class" {
  type    = string
  default = "db.t3.micro"
}

variable "db_engine_version" {
  type    = string
  default = "8.0"
}

variable "db_backup_retention_days" {
  description = <<-EOT
    RDS automated-backup retention. 0 disables backups (a lab 11 talking point).
    Default kept low (1) because new/personal AWS accounts under free-tier
    restrictions reject higher values: CreateDBInstance fails with
    "FreeTierRestrictionError: The specified backup retention period exceeds
    the maximum available to free tier customers" above this on some accounts
    (confirmed by hand on a real free-tier-restricted account). Since most
    students taking this course will be on exactly this kind of account, keep
    this low rather than teaching around an account-specific API error.
  EOT
  type        = number
  default     = 1
}

variable "tags" {
  description = "Extra tags merged into every resource."
  type        = map(string)
  default     = {}
}
