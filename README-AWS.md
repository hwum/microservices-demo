# Online Boutique - AWS Deployment

Quick reference for deploying Online Boutique to AWS EKS.

> Note: PRs are validated via GitHub Actions (see `.github/workflows/pr-checks.yaml`).

## 🚀 Quick Start

```bash
./deploy-to-aws.sh
```

That's it! One command deploys everything.

## 📋 What You Need

- AWS CLI
- Terraform
- kubectl
- ADA (for AWS credentials)

## 🌐 Live Demo

**Endpoint:** http://a82f066205230497c9eba56db1d0e5c7-565300457.us-east-1.elb.amazonaws.com/

## 📚 Full Documentation

See [AWSDeployGuide.md](./AWSDeployGuide.md) for complete documentation including:
- Detailed prerequisites
- Architecture diagrams
- Cost estimation
- Troubleshooting guide
- Cleanup instructions

## 🧹 Cleanup

```bash
./cleanup-aws.sh
```

## 💰 Cost

Approximately **$0.30/hour** (~$7/day) while running.

## 🎨 Customizations

This deployment includes:
- ✅ Custom frontend with removed footer banner
- ✅ All 12 microservices
- ✅ Automatic scaling
- ✅ Load balancer configuration

## 📞 Quick Help

**Page not loading?**
```bash
aws elb create-load-balancer-listeners \
  --load-balancer-name a82f066205230497c9eba56db1d0e5c7 \
  --listeners "Protocol=TCP,LoadBalancerPort=80,InstanceProtocol=TCP,InstancePort=30827" \
  --region us-east-1
```

**Check status:**
```bash
kubectl get pods
kubectl get services
```

---

For detailed information, see [AWSDeployGuide.md](./AWSDeployGuide.md)
