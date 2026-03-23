# AWS Event-Driven Microservices Platform

## Overview

A production-style event-driven microservices platform on AWS that demonstrates integration between a Windows-based service, containerized workloads, asynchronous messaging, and managed cloud infrastructure.

**Request flow:**

```
Client → ALB → Windows Service (EC2) → Amazon MQ (RabbitMQ) → Worker (ECS Fargate) → RDS PostgreSQL
```

---

## Architecture

| Component | Technology | Hosting |
|---|---|---|
| Public entry point | Application Load Balancer | AWS ALB |
| API / message publisher | ASP.NET Core + Windows Service | Windows Server 2022 EC2 |
| Message broker | RabbitMQ (AMQPS / TLS) | Amazon MQ |
| Message consumer | .NET Worker | ECS Fargate |
| Database | PostgreSQL 15 | Amazon RDS |
| Secrets | RabbitMQ + DB credentials | AWS Secrets Manager |
| Artifact storage | Windows service ZIP | S3 |
| Container registry | Worker image | ECR |
| Infrastructure | Terraform | — |
| CI/CD | GitHub Actions | — |

---

## Prerequisites

- AWS CLI configured (`aws configure`)
- Terraform >= 1.0
- .NET 8 SDK (local development only)
- Docker (local development only)
- GitHub account (CI/CD)

---

## Repository Structure

```
.
├── api-service/            # ASP.NET Core Windows Service (.NET 8, win-x64)
│   ├── api-service.csproj
│   ├── Program.cs
│   └── Models/
│       └── RequestMessage.cs
├── worker-service/         # .NET Worker — consumes RabbitMQ, writes to PostgreSQL
│   ├── worker-service.csproj
│   ├── Program.cs
│   └── Dockerfile
├── terraform/              # All AWS infrastructure
│   ├── main.tf
│   ├── secrets.tf
│   ├── variables.tf
│   ├── outputs.tf
│   └── tia-key.pub         # EC2 key pair public key (generate before applying)
├── database/
│   └── init.sql            # Table definition (used by local docker-compose)
├── .github/
│   ├── workflows/
│   │   └── deploy.yml
│   └── scripts/
│       └── build-ssm-command.py
└── docker-compose.yml      # Local development only
```

---

## Step 1 — Generate EC2 Key Pair

Before running Terraform, generate the key pair used for the Windows EC2 instance.

```bash
ssh-keygen -t rsa -b 4096 -f terraform/tia-key -N ""
```

- `terraform/tia-key.pub` — read by Terraform (`file("tia-key.pub")`)
- `terraform/tia-key` — keep locally; **never commit this file**

Add to `.gitignore`:

```
terraform/tia-key
terraform/*.tfvars
```

---

## Step 2 — Configure Terraform Variables

Create `terraform/terraform.tfvars` (gitignored) and supply your own values:

```hcl
db_password       = "YourStrongDBPassword1!"
rabbitmq_password = "YourStrongRabbitPassword1!"
admin_cidr        = "YOUR.PUBLIC.IP.ADDRESS/32"
```

`admin_cidr` restricts RDP access to the Windows EC2 to your IP only.

---

## Step 3 — Deploy Infrastructure

```bash
cd terraform
terraform init
terraform plan
terraform apply
```

Terraform creates:

- VPC, subnets, internet gateway, route tables
- Security groups (ALB, Windows EC2, ECS, RDS, RabbitMQ)
- Application Load Balancer + target group + listener
- Windows Server 2022 EC2 (`t3.small`) with IAM role + instance profile
- S3 bucket for Windows service artifacts
- Amazon MQ broker (RabbitMQ, `mq.t3.micro`, single instance, AMQPS)
- RDS PostgreSQL 15 (`db.t3.micro`, private, no public access)
- ECS cluster + Fargate task definition + service for the worker
- ECR repository for the worker image
- AWS Secrets Manager secrets for RabbitMQ and DB credentials
- IAM policies granting ECS and EC2 access to those secrets
- CloudWatch log group for the worker (`/ecs/tia-worker`, 7-day retention)

Note the outputs after apply — you will need them for GitHub secrets:

```bash
terraform output artifacts_bucket        # → ARTIFACTS_BUCKET secret
terraform output windows_ec2_instance_id # → WINDOWS_EC2_INSTANCE_ID secret
terraform output worker_repository_url   # → ECR push URL
```

---

## Step 4 — Configure GitHub Secrets

Go to **Settings → Secrets and variables → Actions** and add:

| Secret | Value |
|---|---|
| `AWS_ACCESS_KEY_ID` | IAM user access key |
| `AWS_SECRET_ACCESS_KEY` | IAM user secret key |
| `ARTIFACTS_BUCKET` | From `terraform output artifacts_bucket` |

---

## Step 5 — Deploy via GitHub Actions

Push to `main` to trigger the pipeline:

```bash
git push origin main
```

The workflow:

1. Publishes the API as a self-contained Windows executable (`win-x64`, single file)
2. Zips and uploads the artifact to S3
3. Sends an SSM `AWS-RunPowerShellScript` command to the Windows EC2 to stop the old service, download the new artifact, extract it, and restart the Windows service
4. Builds the worker Docker image and pushes it to ECR
5. Forces a new ECS deployment so Fargate pulls the latest worker image

---

## Local Development

Start all services locally using Docker Compose:

```bash
docker-compose up --build
```

| Service | URL |
|---|---|
| Worker | (background process) |
| RabbitMQ management UI | http://localhost:15672 |
| PostgreSQL | localhost:5432 |

> **Note:** The API service runs as a Windows Service in production and cannot run in the Linux Docker Compose environment. To test the `/send` endpoint locally, run the API project directly on a Windows machine with `dotnet run`, pointed at local RabbitMQ. Set `MQ_SECRET_NAME` to a Secrets Manager secret that contains a `host` of `localhost`, or override the host resolution in code for local dev.

---

## Testing the Flow

After deployment, retrieve the ALB DNS name:

```bash
terraform output alb_dns_name
```

### Check the API is running

```bash
curl http://<ALB-DNS>/health
# → Healthy
```

### Send a message

```bash
curl -X POST http://<ALB-DNS>/send \
  -H "Content-Type: application/json" \
  -d '{"name": "TestUser", "message": "Hello from the client"}'
# → Message sent to queue
```

### Verify the worker processed it

```
AWS Console → ECS → Clusters → tia-cluster → tia-worker-service → Tasks → Logs
```

Expected log output:

```
Connected to RabbitMQ!
Waiting for messages...
Received message: {"name":"TestUser","message":"Hello from the client"}
Saved to database.
```

### Verify database write

Connect to RDS from within the VPC (e.g., via the Windows EC2 or a bastion) and query:

```sql
SELECT * FROM results ORDER BY created_at DESC LIMIT 10;
```

---

## Credentials and Secrets

Credentials are never stored in plaintext. The platform uses AWS Secrets Manager with two secrets:

| Secret name | Contents | Consumed by |
|---|---|---|
| `tia/rabbitmq-credentials` | `host`, `username`, `password` | Windows API (SDK call at startup), ECS worker (injected at task launch) |
| `tia/db-credentials` | `host`, `username`, `password`, `connection_string` | ECS worker (injected at task launch) |

The Windows EC2 IAM instance profile and the ECS task execution role each have a Secrets Manager read policy scoped to only these two secrets.

---

## Windows Service Deployment

The API is compiled as a self-contained `win-x64` single-file executable and deployed to the EC2 via SSM (no RDP or SSH required):

1. GitHub Actions publishes and zips the executable
2. The zip is uploaded to `s3://<artifacts-bucket>/windows-service/windows-service.zip`
3. An SSM `AWS-RunPowerShellScript` command runs on the EC2 to: stop and delete the old service, download and extract the new zip, set the `MQ_SECRET_NAME` environment variable, register the exe as a Windows service named `TiaWindowsApi`, open port 80 in Windows Firewall, and start the service

The EC2 user data script handles first-time bootstrap using the same sequence on instance creation.

---

## Cleanup

To destroy all resources:

```bash
cd terraform
terraform destroy
```

---

## Author

Lazarus Korir