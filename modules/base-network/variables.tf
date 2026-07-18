# modules/base-network/variables.tf

variable "name" {
  description = "Name prefix for all resources (e.g. northbank-nonprod)."
  type        = string
  default     = "northbank"
}

variable "environment" {
  description = "Environment tag value (nonprod, prod, ...)."
  type        = string
  default     = "nonprod"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Subnets are carved as /24s from this /16."
  type        = string
  default     = "10.20.0.0/16"
}

variable "enable_nat_gateway" {
  description = <<-EOT
    Whether to create a NAT Gateway and the private default route. Set to false
    to simulate 'private instances lost outbound internet' (labs 4/6). Note: a
    NAT Gateway is the main hourly cost in this module.
  EOT
  type        = bool
  default     = true
}

variable "tags" {
  description = "Extra tags merged into every resource."
  type        = map(string)
  default     = {}
}
