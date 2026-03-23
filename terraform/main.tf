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

resource "aws_security_group" "postgres" {
  name   = "tia-postgres-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id, aws_security_group.windows_ec2.id]
    description     = "PostgreSQL from ECS worker and Windows EC2"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rabbitmq" {
  name   = "tia-rabbitmq-sg"
  vpc_id = aws_vpc.main.id

  ingress {
    from_port = 5671
    to_port   = 5671
    protocol  = "tcp"
    security_groups = [
      aws_security_group.ecs.id,
      aws_security_group.windows_ec2.id
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

resource "aws_lb_listener" "listener" {
  load_balancer_arn = aws_lb.alb.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.windows_tg.arn
  }
}

################################
# Windows EC2
################################

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

data "aws_caller_identity" "current" {}

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

resource "aws_instance" "windows_api" {
  ami                         = data.aws_ami.windows_2022.id
  instance_type               = "t3.small"
  subnet_id                   = aws_subnet.subnet1.id
  vpc_security_group_ids      = [aws_security_group.windows_ec2.id]
  iam_instance_profile        = aws_iam_instance_profile.windows_ec2.name
  key_name                    = aws_key_pair.tia.key_name
  user_data_replace_on_change = true

  # NOTE: Use single backslash in PowerShell paths here.
  # Terraform heredoc does not interpret backslashes — they pass through as-is.
  # Do NOT double-escape backslashes in this block.
  user_data = base64encode(<<-POWERSHELL
<powershell>
$ErrorActionPreference = "Stop"
Start-Transcript -Path "C:\setup.log" -Append

Write-Output "Installing AWS CLI..."
Invoke-WebRequest "https://awscli.amazonaws.com/AWSCLIV2.msi" -OutFile "C:\AWSCLIV2.msi"
Start-Process msiexec.exe -ArgumentList '/i C:\AWSCLIV2.msi /quiet /norestart' -Wait
Write-Output "AWS CLI installed."

$aws = "C:\Program Files\Amazon\AWSCLIV2\aws.exe"
New-Item -ItemType Directory -Force -Path "C:\app"

Write-Output "Downloading artifact from S3..."
& $aws s3 cp "s3://${aws_s3_bucket.artifacts.bucket}/windows-service/windows-service.zip" "C:\app\windows-service.zip"

if (-not (Test-Path "C:\app\windows-service.zip")) {
  throw "S3 download failed - zip not found"
}
Write-Output "Download complete."

Write-Output "Extracting..."
Expand-Archive -Path "C:\app\windows-service.zip" -DestinationPath "C:\app" -Force

Write-Output "Setting environment variables..."
[System.Environment]::SetEnvironmentVariable("MQ_SECRET_NAME", "${aws_secretsmanager_secret.rabbitmq.name}", "Machine")

Write-Output "Opening firewall port 80..."
netsh advfirewall firewall add rule name=AllowHTTP80 dir=in action=allow protocol=TCP localport=80

Write-Output "Creating Windows service..."
cmd /c sc create TiaWindowsApi binPath= C:\app\api-service.exe start= auto
cmd /c sc description TiaWindowsApi "TIA Windows API Service"

Write-Output "Starting Windows service..."
cmd /c sc start TiaWindowsApi
Start-Sleep -Seconds 8

$status = cmd /c sc query TiaWindowsApi
Write-Output "Service status: $status"

if ($status -notmatch "RUNNING") {
  throw "Service failed to reach RUNNING state"
}

Write-Output "Setup complete. Service is RUNNING."
Stop-Transcript
</powershell>
POWERSHELL
  )

  tags = { Name = "tia-windows-api" }

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [
    aws_mq_broker.rabbitmq,
    aws_secretsmanager_secret_version.rabbitmq
  ]
}

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

  publicly_accessible    = false
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.postgres.id]
  db_subnet_group_name   = aws_db_subnet_group.postgres_subnet_group.name
}

################################
# Amazon MQ RabbitMQ
################################

resource "aws_mq_broker" "rabbitmq" {
  broker_name         = "tia-rabbitmq"
  engine_type         = "RabbitMQ"
  engine_version      = "3.13"
  host_instance_type  = "mq.t3.micro"
  deployment_mode     = "SINGLE_INSTANCE"
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
################################

resource "aws_ecr_repository" "worker" {
  name         = "tia-worker"
  force_delete = true
}

################################
# IAM Role for ECS
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
# ECS Cluster
################################

resource "aws_ecs_cluster" "cluster" {
  name = "tia-cluster"
}

################################
# Worker Task Definition
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

resource "aws_cloudwatch_log_group" "worker" {
  name              = "/ecs/tia-worker"
  retention_in_days = 7
}

################################
# ECS Worker Service
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