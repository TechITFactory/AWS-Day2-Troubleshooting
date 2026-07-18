# envs/sandbox/variables.tf

variable "region" {
  description = "AWS region for the sandbox environment."
  type        = string
  default     = "us-east-1"
}

variable "name" {
  description = "Base name prefix for all NorthBank resources."
  type        = string
  default     = "northbank"
}

variable "environment" {
  description = "Environment label (nonprod for the course sandbox)."
  type        = string
  default     = "nonprod"
}

variable "vpc_cidr" {
  description = "CIDR for the VPC."
  type        = string
  default     = "10.20.0.0/16"
}

variable "instance_type" {
  description = "Web-tier instance size (keep it small)."
  type        = string
  default     = "t3.micro"
}

variable "create_database" {
  description = <<-EOT
    Provision the RDS MySQL database. Leave false for most labs; set true only
    for labs 9 (RDS), 11 (backups/restore) and 15 (capstone), then destroy
    promptly — RDS is the biggest cost in this course.
  EOT
  type        = bool
  default     = false
}
