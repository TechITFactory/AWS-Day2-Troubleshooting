# envs/sandbox/main.tf
#
# The single Terraform root the labs use. It wires base-network + web-app
# together into one NorthBank environment you can apply once and break many
# times. Every lab's `terraform -chdir=../../envs/sandbox output ...` reads
# from here.

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
  }
}

provider "aws" {
  region = var.region

  # Tag everything so cost (lab 14) and cleanup are easy to audit.
  default_tags {
    tags = {
      Project   = "NorthBank"
      Env       = var.environment
      ManagedBy = "terraform"
      Course    = "aws-day2"
    }
  }
}

module "network" {
  source      = "../../modules/base-network"
  name        = "${var.name}-${var.environment}"
  environment = var.environment
  vpc_cidr    = var.vpc_cidr
}

module "app" {
  source      = "../../modules/web-app"
  name        = "${var.name}-${var.environment}"
  environment = var.environment

  vpc_id                = module.network.vpc_id
  public_subnet_ids     = module.network.public_subnet_ids
  private_subnet_ids    = module.network.private_subnet_ids
  alb_security_group_id = module.network.alb_security_group_id
  app_security_group_id = module.network.app_security_group_id
  db_security_group_id  = module.network.db_security_group_id

  instance_type   = var.instance_type
  create_database = var.create_database # set true for labs 9, 11, 15
}
