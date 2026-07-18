# modules/web-app/main.tf
#
# NorthBank's digital-banking web tier: an ALB in the public subnets in front of
# an Auto Scaling group of web servers in the private subnets, with an optional
# RDS MySQL instance for the app to talk to.
#
# This is the thing the labs break. It takes the base-network module's outputs
# as inputs (VPC, subnets, SGs) so the two compose cleanly.

terraform {
  required_version = ">= 1.3.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">= 3.0"
    }
  }
}

locals {
  common_tags = merge({
    Project   = "NorthBank"
    Env       = var.environment
    ManagedBy = "terraform"
    Module    = "web-app"
  }, var.tags)
}

# Latest Amazon Linux 2023 AMI (SSM-managed, so labs 12/patching have an agent).
data "aws_ssm_parameter" "al2023_ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# ---------------------------------------------------------------------------
# IAM: instance role with SSM (so we can run commands / patch without SSH)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "ec2_assume" {
  statement {
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "instance" {
  name               = "${var.name}-instance-role"
  assume_role_policy = data.aws_iam_policy_document.ec2_assume.json
  tags               = local.common_tags
}

resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# CloudWatch agent policy so lab 2/3 can push custom metrics + logs.
resource "aws_iam_role_policy_attachment" "cw_agent" {
  role       = aws_iam_role.instance.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_instance_profile" "instance" {
  name = "${var.name}-instance-profile"
  role = aws_iam_role.instance.name
  tags = local.common_tags
}

# ---------------------------------------------------------------------------
# Launch template + Auto Scaling group (app tier, private subnets)
# ---------------------------------------------------------------------------
resource "aws_launch_template" "app" {
  name_prefix   = "${var.name}-lt-"
  image_id      = data.aws_ssm_parameter.al2023_ami.value
  instance_type = var.instance_type

  iam_instance_profile {
    arn = aws_iam_instance_profile.instance.arn
  }

  vpc_security_group_ids = [var.app_security_group_id]

  user_data = base64encode(templatefile("${path.module}/user-data.sh", {
    app_name = var.name
  }))

  tag_specifications {
    resource_type = "instance"
    tags          = merge(local.common_tags, { Name = "${var.name}-web" })
  }

  # Enforce IMDSv2 (a common Security Hub finding if left optional — see lab 13).
  metadata_options {
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = local.common_tags
}

resource "aws_autoscaling_group" "app" {
  name                = "${var.name}-asg"
  vpc_zone_identifier = var.private_subnet_ids
  min_size            = var.min_size
  max_size            = var.max_size
  desired_capacity    = var.desired_capacity
  health_check_type   = "ELB" # so the ALB's health check governs instance health (labs 7/8)
  health_check_grace_period = 120

  target_group_arns = [aws_lb_target_group.app.arn]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }

  tag {
    key                 = "Name"
    value               = "${var.name}-web"
    propagate_at_launch = true
  }
}

# ---------------------------------------------------------------------------
# Application Load Balancer (public subnets)
# ---------------------------------------------------------------------------
resource "aws_lb" "app" {
  name               = substr("${var.name}-alb", 0, 32)
  internal           = false
  load_balancer_type = "application"
  security_groups    = [var.alb_security_group_id]
  subnets            = var.public_subnet_ids
  tags               = local.common_tags
}

resource "aws_lb_target_group" "app" {
  name     = substr("${var.name}-tg", 0, 32)
  port     = 80
  protocol = "HTTP"
  vpc_id   = var.vpc_id

  # The health check labs 7/8 depend on. /health is served by user-data.sh.
  health_check {
    path                = var.health_check_path
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 2
  }

  tags = local.common_tags
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.app.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app.arn
  }
}

# ---------------------------------------------------------------------------
# Optional RDS MySQL (lab 9). Off by default to keep cost down.
# ---------------------------------------------------------------------------
resource "random_password" "db" {
  count            = var.create_database ? 1 : 0
  length           = 20
  special          = true
  override_special = "!#$%&*()-_=+[]{}"
}

resource "aws_db_subnet_group" "db" {
  count      = var.create_database ? 1 : 0
  name       = "${var.name}-db-subnets"
  subnet_ids = var.private_subnet_ids
  tags       = local.common_tags
}

resource "aws_db_instance" "db" {
  count      = var.create_database ? 1 : 0
  identifier = "${var.name}-db"

  engine         = "mysql"
  engine_version = var.db_engine_version
  instance_class = var.db_instance_class

  allocated_storage = 20
  storage_type      = "gp3"
  storage_encrypted = true

  db_name  = "northbank"
  username = "nbadmin"
  password = random_password.db[0].result

  db_subnet_group_name   = aws_db_subnet_group.db[0].name
  vpc_security_group_ids = [var.db_security_group_id]

  multi_az            = false # single-AZ for cost; labs 9/11/15 discuss the prod trade-off
  publicly_accessible = false
  skip_final_snapshot = true # sandbox convenience; NEVER do this in prod

  backup_retention_period = var.db_backup_retention_days # 0 disables backups (lab 11 talking point)

  tags = local.common_tags
}
