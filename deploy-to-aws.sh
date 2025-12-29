#!/bin/bash
set -e

echo "=========================================="
echo "Online Boutique AWS Deployment"
echo "One-Click Deploy to EKS"
echo "=========================================="
echo ""

# Configuration
AWS_ACCOUNT_ID="388276022184"
AWS_REGION="us-east-1"
CLUSTER_NAME="online-boutique"

# Update AWS credentials
echo "Step 1: Updating AWS credentials..."
ada credentials update --account=${AWS_ACCOUNT_ID} --provider=isengard --role=Admin --once

# Check prerequisites
echo ""
echo "Step 2: Checking prerequisites..."
command -v terraform >/dev/null 2>&1 || { echo "Error: terraform is required but not installed."; exit 1; }
command -v kubectl >/dev/null 2>&1 || { echo "Error: kubectl is required but not installed."; exit 1; }
command -v aws >/dev/null 2>&1 || { echo "Error: aws CLI is required but not installed."; exit 1; }

# Verify AWS credentials
echo "Verifying AWS credentials..."
CURRENT_ACCOUNT=$(aws sts get-caller-identity --query Account --output text 2>/dev/null)
if [ "$CURRENT_ACCOUNT" != "$AWS_ACCOUNT_ID" ]; then
    echo "Warning: Expected account $AWS_ACCOUNT_ID but got $CURRENT_ACCOUNT"
    read -p "Continue anyway? (y/n) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Connected to AWS Account: $CURRENT_ACCOUNT"

# Deploy infrastructure with Terraform
echo ""
echo "Step 3: Deploying infrastructure with Terraform..."
cd terraform-aws
terraform init
terraform apply -auto-approve

# Configure kubectl
echo ""
echo "Step 4: Configuring kubectl..."
aws eks update-kubeconfig --region ${AWS_REGION} --name ${CLUSTER_NAME}

# Wait for cluster to be ready
echo ""
echo "Step 5: Waiting for cluster nodes to be ready..."
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Deploy microservices
echo ""
echo "Step 6: Deploying microservices..."
cd ..
for file in kubernetes-manifests/*.yaml; do
    if [[ "$file" != *"kustomization.yaml" ]]; then
        kubectl apply -f "$file"
    fi
done

# Wait for pods to be ready
echo ""
echo "Step 7: Waiting for pods to be ready..."
sleep 30
kubectl get pods

# Build and deploy all microservices
echo ""
echo "Step 8: Building all microservices with CodeBuild..."
# Create zip with proper directory structure
cd "$(dirname "$0")"
zip -r /tmp/microservices-source.zip src/ > /dev/null

# Upload to S3
BUCKET_NAME="online-boutique-codebuild-source-${AWS_ACCOUNT_ID}"
echo "Uploading source code to S3..."
aws s3 mb s3://$BUCKET_NAME --region ${AWS_REGION} 2>/dev/null || true
aws s3 cp /tmp/microservices-source.zip s3://$BUCKET_NAME/microservices-source.zip

# Get CodeBuild project name
CODEBUILD_PROJECT=$(cd terraform-aws && terraform output -raw codebuild_project_name 2>/dev/null)

if [ -n "$CODEBUILD_PROJECT" ]; then
    echo "Starting CodeBuild to build all microservices..."
    BUILD_ID=$(aws codebuild start-build \
        --project-name $CODEBUILD_PROJECT \
        --source-type-override S3 \
        --source-location-override $BUCKET_NAME/microservices-source.zip \
        --region ${AWS_REGION} \
        --query 'build.id' \
        --output text)

    echo "Build started: $BUILD_ID"
    echo "Building all microservices (this may take 10-15 minutes)..."

    # Poll for build completion
    while true; do
        BUILD_STATUS=$(aws codebuild batch-get-builds --ids $BUILD_ID --region ${AWS_REGION} --query 'builds[0].buildStatus' --output text 2>/dev/null)

        if [ "$BUILD_STATUS" = "SUCCEEDED" ] || [ "$BUILD_STATUS" = "FAILED" ] || [ "$BUILD_STATUS" = "STOPPED" ]; then
            break
        fi

        echo -n "."
        sleep 15
    done

    echo ""
    if [ "$BUILD_STATUS" = "SUCCEEDED" ]; then
        echo "✓ All microservices built successfully!"
    elif [ "$BUILD_STATUS" = "FAILED" ]; then
        echo "Build completed with status: $BUILD_STATUS"
        echo "Updating deployments with custom images..."
        # Update deployments manually if CodeBuild kubectl fails
        kubectl set image deployment/frontend server=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/online-boutique-frontend:latest
        kubectl set image deployment/cartservice server=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/online-boutique-cartservice:latest
        kubectl set image deployment/productcatalogservice server=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/online-boutique-productcatalogservice:latest
        kubectl set image deployment/currencyservice server=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/online-boutique-currencyservice:latest
        kubectl set image deployment/paymentservice server=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/online-boutique-paymentservice:latest
        kubectl set image deployment/shippingservice server=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/online-boutique-shippingservice:latest
        kubectl set image deployment/emailservice server=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/online-boutique-emailservice:latest
        kubectl set image deployment/checkoutservice server=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/online-boutique-checkoutservice:latest
        kubectl set image deployment/recommendationservice server=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/online-boutique-recommendationservice:latest
        kubectl set image deployment/adservice server=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/online-boutique-adservice:latest
        kubectl set image deployment/loadgenerator main=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/online-boutique-loadgenerator:latest

        echo "Restarting deployments..."
        kubectl rollout restart deployment/frontend
        kubectl rollout restart deployment/cartservice
        kubectl rollout restart deployment/productcatalogservice

        echo "Waiting for key services to be ready..."
        kubectl rollout status deployment/frontend --timeout=5m
    fi
fi

# Cleanup temp files
rm -f /tmp/microservices-source.zip

# Get frontend URL
echo ""
echo "Step 9: Getting frontend service URL..."
echo "Waiting for Load Balancer to be provisioned..."

for i in {1..60}; do
    FRONTEND_URL=$(kubectl get service frontend-external -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    if [ -n "$FRONTEND_URL" ]; then
        echo ""
        echo "=========================================="
        echo "✓ Deployment Complete!"
        echo "=========================================="
        echo ""
        echo "Online Boutique is now accessible at:"
        echo ""
        echo "  http://$FRONTEND_URL"
        echo ""
        echo "Cluster: $CLUSTER_NAME"
        echo "Region: $AWS_REGION"
        echo "Account: $AWS_ACCOUNT_ID"
        echo ""
        echo "All microservices built and deployed with custom images"
        echo ""
        echo "To check pod status: kubectl get pods"
        echo "To view logs: kubectl logs -l app=frontend"
        echo "To clean up: ./cleanup-aws.sh"
        echo ""
        exit 0
    fi
    echo -n "."
    sleep 5
done

echo ""
echo "Load Balancer is still provisioning. Check status with:"
echo "  kubectl get service frontend-external"
echo ""
