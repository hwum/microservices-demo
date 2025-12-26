# Deploy Online Boutique to AWS EKS

This directory contains Terraform configuration to deploy the Online Boutique microservices demo to Amazon EKS.

## Prerequisites

1. AWS CLI installed and configured with credentials for account 388276022184
2. Terraform >= 1.0 installed
3. kubectl installed

## Deployment Steps

### 1. Initialize and Apply Terraform

```bash
cd terraform-aws
terraform init
terraform plan
terraform apply
```

This will create:
- VPC with public and private subnets
- EKS cluster with managed node group (3 t3.medium instances)
- Redis deployment for cart service

### 2. Configure kubectl

After Terraform completes, configure kubectl to connect to your cluster:

```bash
aws eks update-kubeconfig --region us-east-1 --name online-boutique
```

### 3. Deploy the Microservices

Apply the Kubernetes manifests:

```bash
kubectl apply -f ../kubernetes-manifests/
```

### 4. Wait for Pods to be Ready

```bash
kubectl get pods -w
```

Wait until all pods show `Running` status (this may take 5-10 minutes).

### 5. Get the Frontend URL

The frontend service will be exposed via an AWS Load Balancer:

```bash
kubectl get service frontend-external
```

Look for the `EXTERNAL-IP` column. It will show a Load Balancer DNS name like:
`a1234567890abcdef-1234567890.us-east-1.elb.amazonaws.com`

Access the application at: `http://<EXTERNAL-IP>`

Note: It may take a few minutes for the Load Balancer to become active.

## Clean Up

To avoid AWS charges, destroy all resources when done:

```bash
# Delete Kubernetes resources first
kubectl delete -f ../kubernetes-manifests/

# Wait for Load Balancer to be deleted (check AWS console)
# Then destroy Terraform resources
terraform destroy
```

## Estimated Costs

Running this demo will incur AWS charges:
- EKS cluster: ~$0.10/hour
- EC2 instances (3x t3.medium): ~$0.125/hour
- NAT Gateway: ~$0.045/hour
- Load Balancer: ~$0.025/hour

**Total: ~$0.30/hour or ~$7/day**

Make sure to destroy resources when not in use!
