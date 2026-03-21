provider "aws" {
  region = var.region
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

################################
# VPC
################################

resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "tia-vpc" }
}

################################
# Internet Gateway
################################

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags   = { Name = "tia-igw" }
}

################################
# Public Subnets
################################

resource "aws_subnet" "subnet1" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "tia-subnet-1" }
}

resource "aws_subnet" "subnet2" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true
  tags = { Name = "tia-subnet-2" }
}

################################
# Route Table
################################

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "subnet1" {
  subnet_id      = aws_subnet.subnet1.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table_association" "subnet2" {
  subnet_id      = aws_subnet.subnet2.id
  route_table_id = aws_route_table.public.id
}

################################
# Security Groups
################################

# ALB — unchanged, public HTTP ingress
resource "aws_security_group" "alb" {
  name   = "tia-alb-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Public HTTP"
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# CHANGE: new security group for the Windows EC2 instance.
# Ingress port 80 is restricted to the ALB only — the EC2 is not directly
# reachable from the internet on port 80.
# RDP (3389) is open for admin access; restrict to a specific IP in production.
resource "aws_security_group" "windows_ec2" {
  name   = "tia-windows-ec2-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 80
    to_port         = 80
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "HTTP from ALB only"
  }

  ingress {
    from_port   = 3389
    to_port     = 3389
    protocol    = "tcp"
    cidr_blocks = [var.admin_cidr]
    description = "RDP from admin CIDR only"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ECS worker — kept as-is; only the worker runs on ECS now (no more Linux api task)
resource "aws_security_group" "ecs" {
  name   = "tia-ecs-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 5030
    to_port         = 5030
    protocol        = "tcp"
    security_groups = [aws_security_group.alb.id]
    description     = "Kept for local-dev docker-compose parity"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# RDS — unchanged ingress (ECS worker only)
resource "aws_security_group" "postgres" {
  name   = "tia-postgres-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
    description     = "PostgreSQL from ECS worker"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# CHANGE: added windows_ec2 SG to the RabbitMQ ingress rule.
# Previously only the ECS worker could reach the broker.
# Now the Windows service (EC2) also needs AMQPS access to publish messages.
resource "aws_security_group" "rabbitmq" {
  name   = "tia-rabbitmq-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port = 5671
    to_port   = 5671
    protocol  = "tcp"
    security_groups = [
      aws_security_group.ecs.id,
      aws_security_group.windows_ec2.id   # ← new
    ]
    description = "AMQPS from ECS worker and Windows EC2"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

################################
# ALB
################################

resource "aws_lb" "alb" {
  name               = "tia-alb"
  load_balancer_type = "application"
  subnets            = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
  security_groups    = [aws_security_group.alb.id]
}

# CHANGE: replaced `tia-api-tg` (ECS/IP target) with `tia-windows-tg` (EC2/instance target).
# The ALB now routes traffic to the Windows EC2 instance, not a Fargate container.
# Key differences from the original:
#   - port: 5030 → 80  (Windows service listens on port 80)
#   - target_type: "ip" → "instance"  (EC2 instances use instance target type)
#   - health_check path: "/" → "/health"  (dedicated health endpoint)
resource "aws_lb_target_group" "windows_tg" {
  name        = "tia-windows-tg"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.main.id
  target_type = "instance"

  health_check {
    path                = "/health"
    protocol            = "HTTP"
    matcher             = "200"
    interval            = 30
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

# CHANGE: listener now forwards to the Windows target group
resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.windows_tg.arn  # ← was api_tg
  }
}

################################
# Windows EC2 — public-facing service
# CHANGE: entire block is new — this is the Windows-based service
#         required by the assignment (previously missing).
################################

# Resolve the latest Windows Server 2022 Full Base AMI automatically.
# Hardcoding an AMI ID would break when AMIs are updated or in other regions.
data "aws_ami" "windows_2022" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["Windows_Server-2022-English-Full-Base-*"]
  }
  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Needed to make the S3 bucket name globally unique
data "aws_caller_identity" "current" {}

# IAM role for the Windows EC2 instance.
# Grants SSM (for Session Manager access) + S3 read (for artifact downloads).
# secrets.tf attaches the Secrets Manager read policy to this role as well.
resource "aws_iam_role" "windows_ec2_role" {
  name = "tia-windows-ec2-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "windows_ssm" {
  role       = aws_iam_role.windows_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "windows_s3" {
  role       = aws_iam_role.windows_ec2_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonS3ReadOnlyAccess"
}

resource "aws_iam_instance_profile" "windows_ec2" {
  name = "tia-windows-ec2-profile"
  role = aws_iam_role.windows_ec2_role.name
}

# S3 bucket for Windows service deployment artifacts.
# GitHub Actions publishes windows-service.zip here; the EC2 downloads it.
resource "aws_s3_bucket" "artifacts" {
  bucket        = "tia-artifacts-${data.aws_caller_identity.current.account_id}"
  force_destroy = true
  tags          = { Name = "tia-artifacts" }
}

resource "aws_s3_bucket_versioning" "artifacts" {
  bucket = aws_s3_bucket.artifacts.id
  versioning_configuration { status = "Enabled" }
}

resource "aws_key_pair" "tia" {
  key_name   = "tia-key"
  public_key = file("tia-key.pub")
}

# The Windows EC2 instance itself.
resource "aws_instance" "windows_api" {
  ami                    = data.aws_ami.windows_2022.id
  instance_type          = "t3.small"
  subnet_id              = aws_subnet.subnet1.id
  vpc_security_group_ids = [aws_security_group.windows_ec2.id]
  iam_instance_profile   = aws_iam_instance_profile.windows_ec2.name
  key_name = aws_key_pair.tia.key_name
  user_data_replace_on_change = true

  user_data = base64encode(templatefile("${path.module}/../scripts/setup-windows-service.ps1", {
    s3_bucket   = aws_s3_bucket.artifacts.bucket
    s3_key      = "windows-service/windows-service.zip"
    secret_name = aws_secretsmanager_secret.rabbitmq.name
  }))

  tags = { Name = "tia-windows-api" }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_mq_broker.rabbitmq,
    aws_secretsmanager_secret_version.rabbitmq
  ]
}

# Register the Windows EC2 instance with the ALB target group.
# This is what connects the ALB listener → EC2 instance.
resource "aws_lb_target_group_attachment" "windows" {
  target_group_arn = aws_lb_target_group.windows_tg.arn
  target_id        = aws_instance.windows_api.id
  port             = 80
}

################################
# DB Subnet Group
################################

resource "aws_db_subnet_group" "postgres_subnet_group" {
  name       = "tia-postgres-subnet-group"
  subnet_ids = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
}

################################
# RDS PostgreSQL
################################

resource "aws_db_instance" "postgres" {
  identifier        = "tia-postgres"
  engine            = "postgres"
  engine_version    = "15"
  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_name  = "postgres"
  username = var.db_username
  password = var.db_password

  # CHANGE: was `true` — this is a security risk.
  # The RDS instance was internet-accessible with a public IP.
  # Only the ECS worker needs to reach it, and only via the
  # tia-postgres-sg security group rule. Setting false means
  # the endpoint resolves to a private IP inside the VPC only.
  publicly_accessible = false

  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.postgres.id]
  db_subnet_group_name   = aws_db_subnet_group.postgres_subnet_group.name
}

################################
# Amazon MQ RabbitMQ — unchanged
################################

resource "aws_mq_broker" "rabbitmq" {
  broker_name        = "tia-rabbitmq"
  engine_type        = "RabbitMQ"
  engine_version     = "3.13"
  host_instance_type = "mq.t3.micro"
  deployment_mode    = "SINGLE_INSTANCE"
  publicly_accessible = false

  subnet_ids      = [aws_subnet.subnet1.id]
  security_groups = [aws_security_group.rabbitmq.id]

  auto_minor_version_upgrade = true

  user {
    username = var.rabbitmq_username
    password = var.rabbitmq_password
  }
}

################################
# ECR
# CHANGE: removed tia-api repository.
# The Linux api-service container is no longer deployed to AWS —
# the Windows EC2 service takes over the public-facing role.
# The tia-api ECR repo is kept locally for docker-compose only;
# it does not need to exist in AWS.
################################

resource "aws_ecr_repository" "worker" {
  name         = "tia-worker"
  force_delete = true
}

################################
# IAM Role for ECS — unchanged
# (secrets.tf attaches the Secrets Manager policy to this role)
################################

resource "aws_iam_role" "ecs_execution_role" {
  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy_attachment" "ecs_execution_role_policy" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

################################
# ECS Cluster — unchanged
################################

resource "aws_ecs_cluster" "cluster" {
  name = "tia-cluster"
}

################################
# CHANGE: removed aws_ecs_task_definition.api_task and
#         aws_ecs_service.api_service entirely.
# The Linux api-service no longer runs in AWS — Windows EC2 handles that role.
################################

################################
# Worker Task Definition
# CHANGE: replaced plaintext `environment` block with `secrets` block.
#
# Before:
#   environment = [{ name = "DB_CONNECTION", value = "Host=...;Password=PLAINTEXT..." }]
#
# After:
#   secrets = [{ name = "DB_CONNECTION", valueFrom = "<secret-arn>:connection_string::" }]
#
# The ECS agent fetches the value at task launch time using the execution role.
# The connection string (with password) never appears in the task definition
# JSON, Terraform state, or ECS console as readable text.
#
# CHANGE: added RABBITMQ_HOST, RABBITMQ_USER, RABBITMQ_PASS via secrets.
# Previously only DB_CONNECTION was passed and RABBITMQ_HOST was hardcoded
# to "rabbitmq" in the worker source code — which meant it could never
# connect to Amazon MQ in production.
#
# CHANGE: added logConfiguration so worker logs go to CloudWatch.
################################

resource "aws_ecs_task_definition" "worker_task" {
  family                   = "tia-worker"
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  execution_role_arn       = aws_iam_role.ecs_execution_role.arn
  cpu                      = 256
  memory                   = 512

  container_definitions = jsonencode([
    {
      name      = "worker"
      image     = "${aws_ecr_repository.worker.repository_url}:latest"
      essential = true

      # Secrets Manager injection — ECS agent resolves these at task launch.
      # Syntax: "<secret-arn>:<json-key>::" extracts a specific key from
      # a JSON-format secret.
      secrets = [
        {
          name      = "DB_CONNECTION"
          valueFrom = "${aws_secretsmanager_secret.db.arn}:connection_string::"
        },
        {
          name      = "RABBITMQ_HOST"
          valueFrom = "${aws_secretsmanager_secret.rabbitmq.arn}:host::"
        },
        {
          name      = "RABBITMQ_USER"
          valueFrom = "${aws_secretsmanager_secret.rabbitmq.arn}:username::"
        },
        {
          name      = "RABBITMQ_PASS"
          valueFrom = "${aws_secretsmanager_secret.rabbitmq.arn}:password::"
        }
      ]

      # Non-sensitive config — RABBITMQ_TLS=1 tells the worker to use port 5671 + TLS.
      # Amazon MQ only accepts AMQPS; plain AMQP will be rejected.
      environment = [
        { name = "RABBITMQ_TLS", value = "1" }
      ]

      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = "/ecs/tia-worker"
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "ecs"
        }
      }
    }
  ])
}

# CHANGE: new — CloudWatch log group for worker container output.
# Without this the task definition's logConfiguration will fail to create log streams.
resource "aws_cloudwatch_log_group" "worker" {
  name              = "/ecs/tia-worker"
  retention_in_days = 7
}

################################
# ECS Worker Service — unchanged
################################

resource "aws_ecs_service" "worker_service" {
  name            = "tia-worker-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.worker_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  network_configuration {
    subnets          = [aws_subnet.subnet1.id, aws_subnet.subnet2.id]
    security_groups  = [aws_security_group.ecs.id]
    assign_public_ip = true
  }
}
