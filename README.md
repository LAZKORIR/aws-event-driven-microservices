# 🚀 AWS Event-Driven Microservices System

## 📌 Overview

This project implements a complete **event-driven microservices architecture** using:

* **ASP.NET Core API** (public entry point)
* **RabbitMQ (Amazon MQ)** for messaging
* **Worker Service (Containerized)** for processing
* **PostgreSQL (Amazon RDS)** for persistence
* **AWS ECS (Fargate)** for container orchestration
* **AWS ECR** for container registry
* **Terraform** for Infrastructure as Code

---

## 🏗️ Architecture

```
Client
   ↓
API (ECS Fargate)
   ↓
RabbitMQ (Amazon MQ)
   ↓
Worker (ECS Fargate)
   ↓
PostgreSQL (RDS)
```

---

## ✅ Prerequisites

Make sure you have:

* AWS CLI configured (`aws configure`)
* Docker installed
* Terraform installed
* .NET 8 SDK (for local development)
* VS Code (recommended)

---

## 🧪 Step 1 — Run Locally (Optional)

Start services using Docker Compose:

```bash
docker-compose up --build
```

Services:

* API → http://localhost:5030
* RabbitMQ UI → http://localhost:15672
* PostgreSQL → localhost:5432

---

## ☁️ Step 2 — Deploy Infrastructure (Terraform)

### Navigate to Terraform folder

```bash
cd terraform
```

### Initialize Terraform

```bash
terraform init
```

### Review plan

```bash
terraform plan
```

### Apply infrastructure

```bash
terraform apply
```

Type:

```
yes
```

---

## 📦 Terraform Creates

* VPC + Subnets + Internet Gateway
* Security Group
* RDS PostgreSQL
* Amazon MQ (RabbitMQ)
* ECS Cluster
* ECS Services (API + Worker)
* ECR Repositories

---

## 📤 Step 3 — Build Docker Images

From project root:

```bash
docker build -t tia-api ./api-service
docker build -t tia-worker ./worker-service
```

---

## 🔐 Step 4 — Login to AWS ECR

```bash
aws ecr get-login-password --region us-east-1 \
| docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
```

---

## 🏷️ Step 5 — Tag Images

```bash
docker tag tia-api:latest <api_repository_url>:latest
docker tag tia-worker:latest <worker_repository_url>:latest
```

---

## 🚀 Step 6 — Push Images

```bash
docker push <api_repository_url>:latest
docker push <worker_repository_url>:latest
```

---

## 🔄 Step 7 — Restart ECS Services

Force ECS to pull latest images:

```bash
aws ecs update-service \
--cluster tia-cluster \
--service tia-api-service \
--force-new-deployment \
--region us-east-1
```

```bash
aws ecs update-service \
--cluster tia-cluster \
--service tia-worker-service \
--force-new-deployment \
--region us-east-1
```

---

## 🔍 Step 8 — Verify Deployment

Go to AWS Console:

```
ECS → Clusters → tia-cluster → Services
```

Ensure:

```
Running tasks = 1
```

---

## 🧪 Step 9 — Test Flow

1. Send request to API
2. API publishes message to RabbitMQ
3. Worker consumes message
4. Worker stores result in PostgreSQL

---

## 📊 Step 10 — View Logs

```
ECS → Worker Service → Tasks → Logs
```

Expected logs:

```
Received message
Saved to database
```

---

## 🔐 Credentials Handling

* DB credentials passed via environment variables
* RabbitMQ credentials configured in Terraform
* Can be improved using **AWS Secrets Manager**

---

## ⚠️ Notes

* API is not publicly exposed yet (no Load Balancer)
* Security group allows all traffic (for demo purposes)

---

## 🚀 Future Improvements

* Add Application Load Balancer (public API access)
* Use AWS Secrets Manager for credentials
* Add CloudWatch logging
* Enable auto-scaling for ECS services
* Restrict security group rules

---

## 🧹 Cleanup

To destroy all resources:

```bash
terraform destroy
```

---

## 🎯 Summary

This project demonstrates:

* Event-driven architecture
* Container orchestration with ECS
* Messaging with RabbitMQ
* Database integration with RDS
* Infrastructure as Code with Terraform

---

## 👨‍💻 Author

Your Name

---
