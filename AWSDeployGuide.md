# Online Boutique - AWS Deployment Guide

Complete guide for deploying the Online Boutique microservices demo application to Amazon Web Services (AWS) using Amazon EKS (Elastic Kubernetes Service).

## Table of Contents

- [Overview](#overview)
- [Architecture](#architecture)
- [Prerequisites](#prerequisites)
- [Quick Start](#quick-start)
- [What Gets Deployed](#what-gets-deployed)
- [Customizations](#customizations)
- [Cost Estimation](#cost-estimation)
- [Troubleshooting](#troubleshooting)
- [Cleanup](#cleanup)

## Overview

This deployment uses:
- **Amazon EKS** for Kubernetes orchestration
- **Terraform** for infrastructure as code
- **AWS CodeBuild** for building custom Docker images
- **Amazon ECR** for container image registry
- **Application Load Balancer** for external access

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                         AWS Cloud                            │
│                                                              │
│  ┌────────────────────────────────────────────────────────┐ │
│  │                    VPC (10.0.0.0/16)                   │ │
│  │                                                         │ │
│  │  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐ │ │
│  │  │ Public Subnet│  │ Public Subnet│  │ Public Subnet│ │ │
│  │  │   AZ-1       │  │   AZ-2       │  │   AZ-3       │ │ │
│  │  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘ │ │
│  │         │                 │                 │          │ │
│  │  ┌──────▼───────┐  ┌──────▼───────┐  ┌──────▼───────┐ │ │
│  │  │Private Subnet│  │Private Subnet│  │Private Subnet│ │ │
│  │  │   AZ-1       │  │   AZ-2       │  │   AZ-3       │ │ │
│  │  │              │  │              │  │              │ │ │
│  │  │ ┌──────────┐ │  │ ┌──────────┐ │  │ ┌──────────┐ │ │ │
│  │  │ │EKS Node  │ │  │ │EKS Node  │ │  │ │EKS Node  │ │ │ │
│  │  │ │t3.medium │ │  │ │t3.medium │ │  │ │t3.medium │ │ │ │
│  │  │ └──────────┘ │  │ └──────────┘ │  │ └──────────┘ │ │ │
│  │  └──────────────┘  └──────────────┘  └──────────────┘ │ │
│  │                                                         │ │
│  │  ┌────────────────────────────────────────────────┐   │ │
│  │  │     Application Load Balancer (Internet)       │   │ │
│  │  └────────────────────────────────────────────────┘   │ │
│  └─────────────────────────────────────────────────────────┘ │
│                                                              │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐         │
│  │     ECR     │  │  CodeBuild  │  │     S3      │         │
│  │  (Images)   │  │  (Builder)  │  │  (Source)   │         │
│  └─────────────┘  └─────────────┘  └─────────────┘         │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

### Required Tools

1. **AWS CLI** (v2.x or later)
   ```bash
   # macOS
   brew install awscli

   # Linux
   curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
   unzip awscliv2.zip
   sudo ./aws/install
   ```

2. **Terraform** (v1.0 or later)
   ```bash
   # macOS
   brew install terraform

   # Linux
   wget https://releases.hashicorp.com/terraform/1.6.0/terraform_1.6.0_linux_amd64.zip
   unzip terraform_1.6.0_linux_amd64.zip
   sudo mv terraform /usr/local/bin/
   ```

3. **kubectl** (v1.28 or later)
   ```bash
   # macOS
   brew install kubectl

   # Linux
   curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
   sudo install -o root -g root -m 0755 kubectl /usr/local/bin/kubectl
   ```

4. **ADA** (for AWS credential management - Amazon internal tool)
   ```bash
   ada credentials update --account=388276022184 --provider=isengard --role=Admin --once
   ```

### AWS Account Requirements

- AWS Account ID: **388276022184**
- IAM permissions for:
  - EKS cluster creation
  - VPC and networking
  - EC2 instances
  - ECR repositories
  - CodeBuild projects
  - S3 buckets
  - IAM roles and policies

## Quick Start

### One-Click Deployment

```bash
# Clone the repository
git clone https://github.com/GoogleCloudPlatform/microservices-demo.git
cd microservices-demo

# Make the script executable
chmod +x deploy-to-aws.sh

# Run the deployment
./deploy-to-aws.sh
```

The script will:
1. ✅ Update AWS credentials
2. ✅ Verify prerequisites
3. ✅ Deploy infrastructure with Terraform
4. ✅ Configure kubectl
5. ✅ Deploy all microservices
6. ✅ Build custom frontend (with removed footer)
7. ✅ Provide the application URL

**Estimated deployment time:** 15-20 minutes

### Access Your Application

After deployment completes, you'll see:

```
==========================================
✓ Deployment Complete!
==========================================

Online Boutique is now accessible at:

  http://a82f066205230497c9eba56db1d0e5c7-565300457.us-east-1.elb.amazonaws.com/

Cluster: online-boutique
Region: us-east-1
Account: 388276022184
```

**Live Demo Endpoint:**
```
http://a82f066205230497c9eba56db1d0e5c7-565300457.us-east-1.elb.amazonaws.com/
```

> **Note:** The Load Balancer may take 2-5 minutes to become fully active after deployment.

## What Gets Deployed

### Infrastructure (Terraform)

| Resource | Type | Configuration |
|----------|------|---------------|
| VPC | Network | 10.0.0.0/16 CIDR |
| Public Subnets | Network | 3 subnets across AZs |
| Private Subnets | Network | 3 subnets across AZs |
| NAT Gateway | Network | Single NAT for cost optimization |
| Internet Gateway | Network | For public subnet access |
| EKS Cluster | Compute | Kubernetes 1.31 |
| EKS Node Group | Compute | 3x t3.medium instances |
| ECR Repository | Registry | For custom frontend images |
| CodeBuild Project | CI/CD | For building Docker images |
| IAM Roles | Security | For EKS and CodeBuild |
| Security Groups | Security | For cluster and nodes |

### Microservices (Kubernetes)

| Service | Language | Description |
|---------|----------|-------------|
| frontend | Go | Web UI (custom build with removed footer) |
| cartservice | C# | Shopping cart management |
| productcatalogservice | Go | Product catalog |
| currencyservice | Node.js | Currency conversion |
| paymentservice | Node.js | Payment processing (mock) |
| shippingservice | Go | Shipping cost calculation |
| emailservice | Python | Order confirmation emails (mock) |
| checkoutservice | Go | Order orchestration |
| recommendationservice | Python | Product recommendations |
| adservice | Java | Contextual advertisements |
| loadgenerator | Python/Locust | Traffic simulation |
| redis-cart | Redis | Cart data storage |

## Customizations

### Custom Frontend

The deployed frontend includes these customizations:

1. **Removed Footer Banner**
   - Original demo warning banner removed
   - Copyright notice removed
   - Session/Request ID removed
   - Deployment details removed
   - Entire red footer section removed

### Modifying the Frontend

To make additional changes:

1. Edit files in `src/frontend/`
2. Run the deployment script again:
   ```bash
   ./deploy-to-aws.sh
   ```

The script will automatically rebuild and deploy your changes.

## Cost Estimation

### Hourly Costs

| Resource | Cost/Hour | Notes |
|----------|-----------|-------|
| EKS Cluster | $0.10 | Control plane |
| EC2 Instances (3x t3.medium) | $0.125 | Worker nodes |
| NAT Gateway | $0.045 | Data transfer extra |
| Application Load Balancer | $0.025 | Data transfer extra |
| **Total** | **~$0.30/hour** | **~$7/day** |

### Additional Costs

- **Data Transfer:** Varies by usage
- **ECR Storage:** $0.10/GB/month
- **S3 Storage:** Minimal (source code only)
- **CloudWatch Logs:** Minimal

### Cost Optimization Tips

1. **Stop when not in use:**
   ```bash
   ./cleanup-aws.sh
   ```

2. **Scale down nodes:**
   ```bash
   kubectl scale deployment --all --replicas=0
   ```

3. **Use Spot Instances:** Modify Terraform to use spot instances for ~70% savings

## Troubleshooting

### Common Issues

#### 1. AWS Credentials Error

**Problem:** `Error: AWS credentials not configured`

**Solution:**
```bash
ada credentials update --account=388276022184 --provider=isengard --role=Admin --once
# Or configure manually
aws configure
```

#### 2. Terraform State Lock

**Problem:** `Error acquiring the state lock`

**Solution:**
```bash
cd terraform-aws
terraform force-unlock <LOCK_ID>
```

#### 3. Pods Not Starting

**Problem:** Pods stuck in `Pending` or `ImagePullBackOff`

**Solution:**
```bash
# Check pod status
kubectl describe pod <pod-name>

# Check node resources
kubectl top nodes

# Restart deployment
kubectl rollout restart deployment/<deployment-name>
```

#### 4. Load Balancer Not Accessible

**Problem:** Cannot access the application URL

**Solution:**
```bash
# Check service status
kubectl get service frontend-external

# Check security groups
aws ec2 describe-security-groups --region us-east-1

# Wait longer (can take 5-10 minutes)
```

#### 5. Page Not Loading (Load Balancer Listener Issue)

**Problem:** Load Balancer exists but page doesn't load or shows connection refused

**Solution:** The Load Balancer may be missing the listener configuration. Add it manually:

```bash
# Get the Load Balancer name from the service
LB_NAME=$(kubectl get service frontend-external -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' | cut -d'-' -f1)

# Get the NodePort
NODE_PORT=$(kubectl get service frontend-external -o jsonpath='{.spec.ports[0].nodePort}')

# Create the listener
aws elb create-load-balancer-listeners \
  --load-balancer-name ${LB_NAME} \
  --listeners "Protocol=TCP,LoadBalancerPort=80,InstanceProtocol=TCP,InstancePort=${NODE_PORT}" \
  --region us-east-1
```

**Example with actual values:**
```bash
aws elb create-load-balancer-listeners \
  --load-balancer-name a82f066205230497c9eba56db1d0e5c7 \
  --listeners "Protocol=TCP,LoadBalancerPort=80,InstanceProtocol=TCP,InstancePort=30827" \
  --region us-east-1
```

After running this command, wait 1-2 minutes and try accessing the URL again.

#### 6. CodeBuild Fails

**Problem:** Custom frontend build fails

**Solution:**
```bash
# Check CodeBuild logs
aws logs tail /aws/codebuild/online-boutique-frontend --region us-east-1 --follow

# Manually update deployment with existing image
kubectl set image deployment/frontend server=388276022184.dkr.ecr.us-east-1.amazonaws.com/online-boutique-frontend:latest
```

### Useful Commands

```bash
# Check all pods
kubectl get pods

# Check pod logs
kubectl logs -f <pod-name>

# Check service endpoints
kubectl get services

# Check node status
kubectl get nodes

# Describe a resource
kubectl describe pod <pod-name>

# Get cluster info
kubectl cluster-info

# Check Terraform state
cd terraform-aws && terraform show

# View CodeBuild builds
aws codebuild list-builds-for-project --project-name online-boutique-frontend-build --region us-east-1
```

## Cleanup

### Complete Cleanup

To delete all AWS resources and avoid charges:

```bash
./cleanup-aws.sh
```

This will:
1. Delete all Kubernetes resources
2. Wait for Load Balancer deletion
3. Delete S3 bucket and contents
4. Delete ECR images
5. Destroy all Terraform-managed infrastructure

**Warning:** This action is irreversible!

### Partial Cleanup

To keep infrastructure but stop services:

```bash
# Scale down all deployments
kubectl scale deployment --all --replicas=0

# Or delete specific deployments
kubectl delete deployment <deployment-name>
```

## Additional Resources

- [Amazon EKS Documentation](https://docs.aws.amazon.com/eks/)
- [Terraform AWS Provider](https://registry.terraform.io/providers/hashicorp/aws/latest/docs)
- [Kubernetes Documentation](https://kubernetes.io/docs/)
- [Original Project Repository](https://github.com/GoogleCloudPlatform/microservices-demo)

## Support

For issues or questions:
1. Check the [Troubleshooting](#troubleshooting) section
2. Review AWS CloudWatch logs
3. Check Kubernetes events: `kubectl get events`
4. Review Terraform logs in `terraform-aws/`

## License

This deployment configuration is provided as-is. The Online Boutique application is licensed under Apache License 2.0.

---

**Last Updated:** December 26, 2025
**Deployment Version:** 1.0
**Kubernetes Version:** 1.31
**Terraform Version:** >= 1.0
