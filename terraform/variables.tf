variable "region" {
  default = "us-east-1"
}

variable "db_username" {
  description = "RDS PostgreSQL master username"
  type        = string
  sensitive   = true
  default     = "postgres"
}

variable "db_password" {
  description = "RDS PostgreSQL master password (min 8 chars)"
  type        = string
  sensitive   = true
  default     = "PostgresPassword123!"
}

variable "rabbitmq_username" {
  description = "Amazon MQ RabbitMQ admin username"
  type        = string
  sensitive   = true
  default     = "rabbitadmin"
}

variable "rabbitmq_password" {
  description = "Amazon MQ RabbitMQ admin password (min 12 chars — Amazon MQ requirement)"
  type        = string
  sensitive   = true
  default     = "RabbitMQPassword123!"
}

variable "windows_ec2_key_pair" {
  description = "EC2 key pair name for Windows EC2 access"
  type        = string
  default = "tia-key"
}

variable "admin_cidr" {
  description = "Admin public IP/CIDR allowed to RDP to Windows EC2"
  type        = string
  default = "172.58.180.72/32"
}
