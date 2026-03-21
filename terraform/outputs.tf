# CHANGE: replaced postgres_endpoint and api_repository_url with
#         more useful outputs for the updated architecture.
# Added: alb_dns_name, windows_ec2_instance_id, windows_ec2_public_ip,
#        artifacts_bucket, and the two secret ARNs.

output "alb_dns_name" {
  description = "Public DNS of the ALB — use this to POST /send"
  value       = aws_lb.alb.dns_name
}

output "windows_ec2_instance_id" {
  description = "Instance ID of the Windows EC2 — needed as a GitHub Actions secret for SSM deployment"
  value       = aws_instance.windows_api.id
}

output "windows_ec2_public_ip" {
  description = "Public IP of the Windows EC2 (for RDP or direct testing)"
  value       = aws_instance.windows_api.public_ip
}

output "artifacts_bucket" {
  description = "S3 bucket name for Windows service zip artifacts — needed as a GitHub Actions secret"
  value       = aws_s3_bucket.artifacts.bucket
}

output "rabbitmq_endpoint" {
  description = "Amazon MQ AMQPS endpoint (stored in Secrets Manager — provided here for reference)"
  value       = aws_mq_broker.rabbitmq.instances[0].endpoints[0]
}

output "worker_repository_url" {
  description = "ECR URL for the worker image — used by GitHub Actions to push and by ECS to pull"
  value       = aws_ecr_repository.worker.repository_url
}

# CHANGE: postgres_endpoint is no longer publicly exposed.
# Kept as an output for debugging but marked sensitive because
# it contains the hostname used with credentials.
output "postgres_endpoint" {
  description = "RDS endpoint (VPC-internal — not publicly reachable)"
  value       = aws_db_instance.postgres.endpoint
  sensitive   = true
}

output "mq_secret_arn" {
  description = "ARN of the RabbitMQ secret in Secrets Manager"
  value       = aws_secretsmanager_secret.rabbitmq.arn
  sensitive   = true
}

output "db_secret_arn" {
  description = "ARN of the DB secret in Secrets Manager"
  value       = aws_secretsmanager_secret.db.arn
  sensitive   = true
}

output "windows_ec2_console_command" {
  value = "aws ec2 get-console-output --instance-id ${aws_instance.windows_api.id} --latest --region ${var.region}"
}
