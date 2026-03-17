output "postgres_endpoint" {
  value = aws_db_instance.postgres.endpoint
}

output "rabbitmq_endpoint" {
  value = aws_mq_broker.rabbitmq.instances[0].endpoints[0]
}

output "api_repository_url" {
  value = aws_ecr_repository.api.repository_url
}

output "worker_repository_url" {
  value = aws_ecr_repository.worker.repository_url
}