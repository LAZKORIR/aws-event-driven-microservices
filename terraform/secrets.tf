# ── secrets.tf ─────────────────────────────────────────────────────────────────
# NEW FILE — all AWS Secrets Manager resources.
#
# Assignment requirement #6: credentials retrieved from a secrets management system.
#
# Two secrets are created:
#   tia/rabbitmq-credentials  — consumed by the Windows EC2 service at runtime
#                               and injected into the ECS worker task at launch
#   tia/db-credentials        — injected into the ECS worker task at launch
#
# ECS injection works via the `secrets` block in the task definition (see main.tf).
# The ECS agent fetches the value from Secrets Manager and injects it as an
# environment variable inside the container. The value never appears as plaintext
# in the task definition JSON or in Terraform state.
#
# The Windows service calls GetSecretValue at startup via the AWS SDK,
# authenticated through its EC2 IAM instance profile (also in main.tf).
# ───────────────────────────────────────────────────────────────────────────────

################################
# RabbitMQ secret
################################

resource "aws_secretsmanager_secret" "rabbitmq" {
  name                    = "tia/rabbitmq-credentials"
  description             = "Amazon MQ RabbitMQ credentials — used by Windows service and ECS worker"
  recovery_window_in_days = 0   # immediate deletion; increase to 7+ in production
}

resource "aws_secretsmanager_secret_version" "rabbitmq" {
  secret_id = aws_secretsmanager_secret.rabbitmq.id

  secret_string = jsonencode({
    host     = replace(aws_mq_broker.rabbitmq.instances[0].endpoints[0], "amqps://", "")
    username = var.rabbitmq_username
    password = var.rabbitmq_password
  })
}

################################
# Database secret
################################

resource "aws_secretsmanager_secret" "db" {
  name                    = "tia/db-credentials"
  description             = "RDS PostgreSQL credentials — used by ECS worker"
  recovery_window_in_days = 0
}

resource "aws_secretsmanager_secret_version" "db" {
  secret_id = aws_secretsmanager_secret.db.id

  secret_string = jsonencode({
    host              = aws_db_instance.postgres.address
    username          = var.db_username
    password          = var.db_password
    database          = "postgres"
    # Pre-built Npgsql connection string — referenced directly by the worker
    connection_string = "Host=${aws_db_instance.postgres.address};Username=${var.db_username};Password=${var.db_password};Database=postgres"
  })
}

################################
# IAM policy — read both secrets
################################

# This policy is attached to two principals in main.tf:
#   1. aws_iam_role.ecs_execution_role  — so ECS can inject secrets at task launch
#   2. aws_iam_role.windows_ec2_role    — so the Windows service can call GetSecretValue

data "aws_iam_policy_document" "secrets_read" {
  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret"
    ]
    resources = [
      aws_secretsmanager_secret.rabbitmq.arn,
      aws_secretsmanager_secret.db.arn
    ]
  }
}

resource "aws_iam_policy" "secrets_read" {
  name        = "tia-secrets-read"
  description = "Allows TIA services to read credentials from Secrets Manager"
  policy      = data.aws_iam_policy_document.secrets_read.json
}

# Attach to ECS task execution role
resource "aws_iam_role_policy_attachment" "ecs_secrets" {
  role       = aws_iam_role.ecs_execution_role.name
  policy_arn = aws_iam_policy.secrets_read.arn
}

# Attach to Windows EC2 instance role
resource "aws_iam_role_policy_attachment" "ec2_secrets" {
  role       = aws_iam_role.windows_ec2_role.name
  policy_arn = aws_iam_policy.secrets_read.arn
}
