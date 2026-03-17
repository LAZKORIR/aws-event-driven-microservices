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

  tags = {
    Name = "tia-vpc"
  }
}

################################
# Internet Gateway
################################

resource "aws_internet_gateway" "igw" {

  vpc_id = aws_vpc.main.id

  tags = {
    Name = "tia-igw"
  }
}

################################
# Public Subnets
################################

resource "aws_subnet" "subnet1" {

  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true

  tags = {
    Name = "tia-subnet-1"
  }
}

resource "aws_subnet" "subnet2" {

  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.2.0/24"
  availability_zone       = "us-east-1b"
  map_public_ip_on_launch = true

  tags = {
    Name = "tia-subnet-2"
  }
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

resource "aws_security_group" "ecs" {

  name   = "tia-ecs-sg"
  vpc_id = aws_vpc.main.id

  ingress {

    from_port   = 5030
    to_port     = 5030
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
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
    security_groups = [aws_security_group.ecs.id]
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

    from_port       = 5671
    to_port         = 5671
    protocol        = "tcp"
    security_groups = [aws_security_group.ecs.id]
  }

  egress {

    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

################################
# DB Subnet Group
################################

resource "aws_db_subnet_group" "postgres_subnet_group" {

  name = "tia-postgres-subnet-group"

  subnet_ids = [
    aws_subnet.subnet1.id,
    aws_subnet.subnet2.id
  ]
}

################################
# RDS PostgreSQL
################################

resource "aws_db_instance" "postgres" {

  identifier = "tia-postgres"

  engine         = "postgres"
  engine_version = "15"

  instance_class    = "db.t3.micro"
  allocated_storage = 20

  db_name  = "postgres"
  username = var.db_username
  password = var.db_password

  publicly_accessible = true
  skip_final_snapshot = true

  vpc_security_group_ids = [
    aws_security_group.postgres.id
  ]

  db_subnet_group_name = aws_db_subnet_group.postgres_subnet_group.name
}

################################
# Amazon MQ RabbitMQ
################################

resource "aws_mq_broker" "rabbitmq" {

  broker_name = "tia-rabbitmq"

  engine_type    = "RabbitMQ"
  engine_version = "3.13"

  host_instance_type = "mq.t3.micro"
  deployment_mode    = "SINGLE_INSTANCE"

  publicly_accessible = false

  subnet_ids = [
    aws_subnet.subnet1.id
  ]

  security_groups = [
    aws_security_group.rabbitmq.id
  ]

  auto_minor_version_upgrade = true

  user {

    username = var.rabbitmq_username
    password = var.rabbitmq_password
  }
}

################################
# ECR
################################

resource "aws_ecr_repository" "api" {

  name = "tia-api"
  force_delete = true
}

resource "aws_ecr_repository" "worker" {

  name = "tia-worker"
  force_delete = true
}

################################
# IAM Role for ECS
################################

resource "aws_iam_role" "ecs_execution_role" {

  name = "ecsTaskExecutionRole"

  assume_role_policy = jsonencode({

    Version = "2012-10-17"

    Statement = [
      {
        Effect = "Allow"

        Principal = {
          Service = "ecs-tasks.amazonaws.com"
        }

        Action = "sts:AssumeRole"
      }
    ]
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
# API Task Definition
################################

resource "aws_ecs_task_definition" "api_task" {

  family                   = "tia-api"
  requires_compatibilities = ["FARGATE"]

  network_mode       = "awsvpc"
  execution_role_arn = aws_iam_role.ecs_execution_role.arn

  cpu    = 256
  memory = 512

  container_definitions = jsonencode([
    {
      name  = "api"
      image = "${aws_ecr_repository.api.repository_url}:latest"

      essential = true

      portMappings = [
        {
          containerPort = 5030
          protocol      = "tcp"
        }
      ]

      environment = [
        {
          name  = "RABBITMQ_HOST"
          value = replace(aws_mq_broker.rabbitmq.instances[0].endpoints[0], "amqps://", "")
        }
      ]
    }
  ])
}

################################
# Worker Task Definition
################################

resource "aws_ecs_task_definition" "worker_task" {

  family                   = "tia-worker"
  requires_compatibilities = ["FARGATE"]

  network_mode       = "awsvpc"
  execution_role_arn = aws_iam_role.ecs_execution_role.arn

  cpu    = 256
  memory = 512

  container_definitions = jsonencode([
    {
      name  = "worker"
      image = "${aws_ecr_repository.worker.repository_url}:latest"

      essential = true

      environment = [
        {
          name  = "DB_CONNECTION"
          value = "Host=${aws_db_instance.postgres.address};Username=${var.db_username};Password=${var.db_password};Database=postgres"
        }
      ]
    }
  ])
}

################################
# ECS Services
################################

resource "aws_ecs_service" "api_service" {

  name            = "tia-api-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.api_task.arn

  desired_count = 1
  launch_type   = "FARGATE"

  network_configuration {

    subnets = [
      aws_subnet.subnet1.id,
      aws_subnet.subnet2.id
    ]

    security_groups = [
      aws_security_group.ecs.id
    ]

    assign_public_ip = true
  }
}

resource "aws_ecs_service" "worker_service" {

  name            = "tia-worker-service"
  cluster         = aws_ecs_cluster.cluster.id
  task_definition = aws_ecs_task_definition.worker_task.arn

  desired_count = 1
  launch_type   = "FARGATE"

  network_configuration {

    subnets = [
      aws_subnet.subnet1.id,
      aws_subnet.subnet2.id
    ]

    security_groups = [
      aws_security_group.ecs.id
    ]

    assign_public_ip = true
  }
}