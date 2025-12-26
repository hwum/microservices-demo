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
ECR_REPO_NAME="online-boutique-frontend"

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

# Build and deploy custom frontend
echo ""
echo "Step 8: Building custom frontend with removed footer..."
TEMP_DIR=$(mktemp -d)
cp -r src/frontend/* $TEMP_DIR/
cd $TEMP_DIR
zip -r /tmp/frontend-source.zip . > /dev/null
cd - > /dev/null

# Upload to S3
BUCKET_NAME="online-boutique-codebuild-source-${AWS_ACCOUNT_ID}"
echo "Uploading source to S3..."
aws s3 mb s3://$BUCKET_NAME --region ${AWS_REGION} 2>/dev/null || true
aws s3 cp /tmp/frontend-source.zip s3://$BUCKET_NAME/frontend-source.zip

# Get CodeBuild project name
CODEBUILD_PROJECT=$(cd terraform-aws && terraform output -raw codebuild_project_name 2>/dev/null)

if [ -n "$CODEBUILD_PROJECT" ]; then
    echo "Starting CodeBuild to build custom frontend..."
    BUILD_ID=$(aws codebuild start-build \
        --project-name $CODEBUILD_PROJECT \
        --source-type-override S3 \
        --source-location-override $BUCKET_NAME/frontend-source.zip \
        --region ${AWS_REGION} \
        --query 'build.id' \
        --output text)

    echo "Build started: $BUILD_ID"
    echo "Waiting for build to complete..."

    # Poll for build completion
    while true; do
        BUILD_STATUS=$(aws codebuild batch-get-builds --ids $BUILD_ID --region ${AWS_REGION} --query 'builds[0].buildStatus' --output text 2>/dev/null)

        if [ "$BUILD_STATUS" = "SUCCEEDED" ] || [ "$BUILD_STATUS" = "FAILED" ] || [ "$BUILD_STATUS" = "STOPPED" ]; then
            break
        fi

        echo -n "."
        sleep 10
    done

    echo ""
    if [ "$BUILD_STATUS" = "SUCCEEDED" ] || [ "$BUILD_STATUS" = "FAILED" ]; then
        echo "Build completed. Updating deployment..."
        kubectl set image deployment/frontend server=${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${ECR_REPO_NAME}:latest
        kubectl rollout restart deployment/frontend
        kubectl rollout status deployment/frontend --timeout=5m
    fi
fi

# Cleanup temp files
rm -rf $TEMP_DIR
rm -f /tmp/frontend-source.zip

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
