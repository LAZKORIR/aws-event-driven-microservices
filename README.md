# 🚀 AWS Event-Driven Microservices System

## 📌 Overview

This project implements a complete **event-driven microservices architecture** using:

* **ASP.NET Core API** (public entry point)
* **RabbitMQ (Amazon MQ)** for messaging
* **Worker Service (Containerized)** for processing
* **PostgreSQL (Amazon RDS)** for persistence
* **AWS ECS (Fargate)** for container orchestration
* **AWS ECR** for container registry
* **Application Load Balancer (ALB)** for public access
* **GitHub Actions** for CI/CD
* **Terraform** for Infrastructure as Code

---

## 🏗️ Architecture

```id="8q8p4h"
Client
   ↓
ALB (Public Endpoint)
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

## 🌐 Public API Access

After deployment, access the API via:

```id="6d3m2j"
http://<ALB-DNS>/swagger/index.html
```

---

## ✅ Prerequisites

Make sure you have:

* AWS CLI configured (`aws configure`)
* Docker installed
* Terraform installed
* .NET 8 SDK (for local development)
* GitHub account (for CI/CD)

---

## 🧪 Step 1 — Run Locally (Optional)

Start services using Docker Compose:

```bash id="6r4w2t"
docker-compose up --build
```

Services:

* API → http://localhost:5030
* RabbitMQ UI → http://localhost:15672
* PostgreSQL → localhost:5432

---

## ☁️ Step 2 — Deploy Infrastructure (Terraform)

### Navigate to Terraform folder

```bash id="tf1"
cd terraform
```

### Initialize Terraform

```bash id="tf2"
terraform init
```

### Review plan

```bash id="tf3"
terraform plan
```

### Apply infrastructure

```bash id="tf4"
terraform apply
```

Type:

```
yes
```

---

## 📦 Terraform Creates

* VPC + Subnets + Internet Gateway
* Route Tables
* Security Groups
* **Application Load Balancer (ALB)**
* Target Group + Listener
* RDS PostgreSQL
* Amazon MQ (RabbitMQ)
* ECS Cluster
* ECS Services (API + Worker)
* ECR Repositories

---

## 📤 Step 3 — Build Docker Images (Manual Option)

```bash id="bd1"
docker build -t tia-api ./api-service
docker build -t tia-worker ./worker-service
```

---

## 🔐 Step 4 — Login to AWS ECR

```bash id="bd2"
aws ecr get-login-password --region us-east-1 \
| docker login --username AWS --password-stdin <account-id>.dkr.ecr.us-east-1.amazonaws.com
```

---

## 🏷️ Step 5 — Tag Images

```bash id="bd3"
docker tag tia-api:latest <api_repository_url>:latest
docker tag tia-worker:latest <worker_repository_url>:latest
```

---

## 🚀 Step 6 — Push Images

```bash id="bd4"
docker push <api_repository_url>:latest
docker push <worker_repository_url>:latest
```

---

## 🔄 Step 7 — Restart ECS Services

```bash id="bd5"
aws ecs update-service \
--cluster tia-cluster \
--service tia-api-service \
--force-new-deployment \
--region us-east-1
```

```bash id="bd6"
aws ecs update-service \
--cluster tia-cluster \
--service tia-worker-service \
--force-new-deployment \
--region us-east-1
```

---

## 🔄 Step 8 — CI/CD Deployment (Recommended)

This project uses **GitHub Actions** to automate:

* Build Docker images
* Push to ECR
* Deploy to ECS

### Required GitHub Secrets:

```id="gh1"
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
```

### Trigger deployment:

```bash id="gh2"
git push
```

---

## 🔍 Step 9 — Verify Deployment

Go to AWS Console:

```
ECS → Clusters → tia-cluster → Services
```

Ensure:

```
Running tasks = 1
```

---

## 🧪 Step 10 — Test Flow

### 1. Open Swagger

```bash id="ts1"
http://<ALB-DNS>/swagger/index.html
```

### 2. Send request

```json id="ts2"
POST /send
{
  "name": "ComposerUser",
  "message": "Hello System"
}
```

---

## 📊 Step 11 — View Logs

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

* API is exposed via **Application Load Balancer (ALB)**
* ALB performs health checks before routing traffic
* ECS services run in a VPC with controlled access

---

## 🚀 Future Improvements

* HTTPS (SSL via ACM)
* Custom domain (Route53)
* Use AWS Secrets Manager
* Add CloudWatch logging dashboards
* Enable auto-scaling for ECS services
* Add authentication (JWT)

---

## 🧹 Cleanup

To destroy all resources:

```bash id="cl1"
terraform destroy
```

---

## 🎯 Summary

This project demonstrates:

* Event-driven microservices architecture
* Messaging with RabbitMQ
* Container orchestration with ECS Fargate
* CI/CD automation with GitHub Actions
* Infrastructure as Code with Terraform
* Production-ready API exposure using ALB

---

## 👨‍💻 Author

Lazarus Korir
