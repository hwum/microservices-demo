# IAM Role for CodeBuild
resource "aws_iam_role" "codebuild_role" {
  name = "online-boutique-codebuild-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "codebuild.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "codebuild_policy" {
  role = aws_iam_role.codebuild_role.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:GetObjectVersion"
        ]
        Resource = "arn:aws:s3:::online-boutique-codebuild-source-*/*"
      },
      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchCheckLayerAvailability",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchGetImage",
          "ecr:PutImage",
          "ecr:InitiateLayerUpload",
          "ecr:UploadLayerPart",
          "ecr:CompleteLayerUpload"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "eks:DescribeCluster"
        ]
        Resource = module.eks.cluster_arn
      }
    ]
  })
}

# ECR Repositories for all microservices
resource "aws_ecr_repository" "frontend" {
  name                 = "online-boutique-frontend"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository" "cartservice" {
  name                 = "online-boutique-cartservice"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository" "productcatalogservice" {
  name                 = "online-boutique-productcatalogservice"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository" "currencyservice" {
  name                 = "online-boutique-currencyservice"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository" "paymentservice" {
  name                 = "online-boutique-paymentservice"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository" "shippingservice" {
  name                 = "online-boutique-shippingservice"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository" "emailservice" {
  name                 = "online-boutique-emailservice"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository" "checkoutservice" {
  name                 = "online-boutique-checkoutservice"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository" "recommendationservice" {
  name                 = "online-boutique-recommendationservice"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository" "adservice" {
  name                 = "online-boutique-adservice"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
}

resource "aws_ecr_repository" "loadgenerator" {
  name                 = "online-boutique-loadgenerator"
  image_tag_mutability = "MUTABLE"
  image_scanning_configuration {
    scan_on_push = false
  }
}

# CodeBuild Project
resource "aws_codebuild_project" "microservices_build" {
  name          = "online-boutique-microservices-build"
  description   = "Build and deploy all Online Boutique microservices"
  build_timeout = "60"
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_MEDIUM"
    image                       = "aws/codebuild/standard:7.0"
    type                        = "LINUX_CONTAINER"
    image_pull_credentials_type = "CODEBUILD"
    privileged_mode             = true

    environment_variable {
      name  = "AWS_DEFAULT_REGION"
      value = var.aws_region
    }

    environment_variable {
      name  = "AWS_ACCOUNT_ID"
      value = data.aws_caller_identity.current.account_id
    }

    environment_variable {
      name  = "ECR_REGISTRY"
      value = "${data.aws_caller_identity.current.account_id}.dkr.ecr.${var.aws_region}.amazonaws.com"
    }

    environment_variable {
      name  = "EKS_CLUSTER_NAME"
      value = module.eks.cluster_name
    }
  }

  source {
    type      = "NO_SOURCE"
    buildspec = <<-EOT
      version: 0.2
      phases:
        pre_build:
          commands:
            - echo Logging in to Amazon ECR...
            - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $ECR_REGISTRY
            - COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
            - IMAGE_TAG=$${COMMIT_HASH:=latest}
            - echo "Building with tag $IMAGE_TAG"
        build:
          commands:
            - echo Build started on `date`
            - echo Building all microservices...

            # Build Frontend (with custom footer removed)
            - |
              echo "Building frontend..."
              cd src/frontend
              docker build --platform linux/amd64 -t $ECR_REGISTRY/online-boutique-frontend:$IMAGE_TAG -t $ECR_REGISTRY/online-boutique-frontend:latest .
              docker push $ECR_REGISTRY/online-boutique-frontend:$IMAGE_TAG
              docker push $ECR_REGISTRY/online-boutique-frontend:latest
              cd ../..

            # Build Cart Service
            - |
              echo "Building cartservice..."
              cd src/cartservice/src
              docker build --platform linux/amd64 -t $ECR_REGISTRY/online-boutique-cartservice:$IMAGE_TAG -t $ECR_REGISTRY/online-boutique-cartservice:latest .
              docker push $ECR_REGISTRY/online-boutique-cartservice:$IMAGE_TAG
              docker push $ECR_REGISTRY/online-boutique-cartservice:latest
              cd ../../..

            # Build Product Catalog Service
            - |
              echo "Building productcatalogservice..."
              cd src/productcatalogservice
              docker build --platform linux/amd64 -t $ECR_REGISTRY/online-boutique-productcatalogservice:$IMAGE_TAG -t $ECR_REGISTRY/online-boutique-productcatalogservice:latest .
              docker push $ECR_REGISTRY/online-boutique-productcatalogservice:$IMAGE_TAG
              docker push $ECR_REGISTRY/online-boutique-productcatalogservice:latest
              cd ../..

            # Build Currency Service
            - |
              echo "Building currencyservice..."
              cd src/currencyservice
              docker build --platform linux/amd64 -t $ECR_REGISTRY/online-boutique-currencyservice:$IMAGE_TAG -t $ECR_REGISTRY/online-boutique-currencyservice:latest .
              docker push $ECR_REGISTRY/online-boutique-currencyservice:$IMAGE_TAG
              docker push $ECR_REGISTRY/online-boutique-currencyservice:latest
              cd ../..

            # Build Payment Service
            - |
              echo "Building paymentservice..."
              cd src/paymentservice
              docker build --platform linux/amd64 -t $ECR_REGISTRY/online-boutique-paymentservice:$IMAGE_TAG -t $ECR_REGISTRY/online-boutique-paymentservice:latest .
              docker push $ECR_REGISTRY/online-boutique-paymentservice:$IMAGE_TAG
              docker push $ECR_REGISTRY/online-boutique-paymentservice:latest
              cd ../..

            # Build Shipping Service
            - |
              echo "Building shippingservice..."
              cd src/shippingservice
              docker build --platform linux/amd64 -t $ECR_REGISTRY/online-boutique-shippingservice:$IMAGE_TAG -t $ECR_REGISTRY/online-boutique-shippingservice:latest .
              docker push $ECR_REGISTRY/online-boutique-shippingservice:$IMAGE_TAG
              docker push $ECR_REGISTRY/online-boutique-shippingservice:latest
              cd ../..

            # Build Email Service
            - |
              echo "Building emailservice..."
              cd src/emailservice
              docker build --platform linux/amd64 -t $ECR_REGISTRY/online-boutique-emailservice:$IMAGE_TAG -t $ECR_REGISTRY/online-boutique-emailservice:latest .
              docker push $ECR_REGISTRY/online-boutique-emailservice:$IMAGE_TAG
              docker push $ECR_REGISTRY/online-boutique-emailservice:latest
              cd ../..

            # Build Checkout Service
            - |
              echo "Building checkoutservice..."
              cd src/checkoutservice
              docker build --platform linux/amd64 -t $ECR_REGISTRY/online-boutique-checkoutservice:$IMAGE_TAG -t $ECR_REGISTRY/online-boutique-checkoutservice:latest .
              docker push $ECR_REGISTRY/online-boutique-checkoutservice:$IMAGE_TAG
              docker push $ECR_REGISTRY/online-boutique-checkoutservice:latest
              cd ../..

            # Build Recommendation Service
            - |
              echo "Building recommendationservice..."
              cd src/recommendationservice
              docker build --platform linux/amd64 -t $ECR_REGISTRY/online-boutique-recommendationservice:$IMAGE_TAG -t $ECR_REGISTRY/online-boutique-recommendationservice:latest .
              docker push $ECR_REGISTRY/online-boutique-recommendationservice:$IMAGE_TAG
              docker push $ECR_REGISTRY/online-boutique-recommendationservice:latest
              cd ../..

            # Build Ad Service
            - |
              echo "Building adservice..."
              cd src/adservice
              docker build --platform linux/amd64 -t $ECR_REGISTRY/online-boutique-adservice:$IMAGE_TAG -t $ECR_REGISTRY/online-boutique-adservice:latest .
              docker push $ECR_REGISTRY/online-boutique-adservice:$IMAGE_TAG
              docker push $ECR_REGISTRY/online-boutique-adservice:latest
              cd ../..

            # Build Load Generator
            - |
              echo "Building loadgenerator..."
              cd src/loadgenerator
              docker build --platform linux/amd64 -t $ECR_REGISTRY/online-boutique-loadgenerator:$IMAGE_TAG -t $ECR_REGISTRY/online-boutique-loadgenerator:latest .
              docker push $ECR_REGISTRY/online-boutique-loadgenerator:$IMAGE_TAG
              docker push $ECR_REGISTRY/online-boutique-loadgenerator:latest
              cd ../..

        post_build:
          commands:
            - echo Build completed on `date`
            - echo All microservices built and pushed to ECR
            - echo Updating Kubernetes deployments...
            - aws eks update-kubeconfig --region $AWS_DEFAULT_REGION --name $EKS_CLUSTER_NAME
            - kubectl set image deployment/frontend server=$ECR_REGISTRY/online-boutique-frontend:$IMAGE_TAG
            - kubectl set image deployment/cartservice server=$ECR_REGISTRY/online-boutique-cartservice:$IMAGE_TAG
            - kubectl set image deployment/productcatalogservice server=$ECR_REGISTRY/online-boutique-productcatalogservice:$IMAGE_TAG
            - kubectl set image deployment/currencyservice server=$ECR_REGISTRY/online-boutique-currencyservice:$IMAGE_TAG
            - kubectl set image deployment/paymentservice server=$ECR_REGISTRY/online-boutique-paymentservice:$IMAGE_TAG
            - kubectl set image deployment/shippingservice server=$ECR_REGISTRY/online-boutique-shippingservice:$IMAGE_TAG
            - kubectl set image deployment/emailservice server=$ECR_REGISTRY/online-boutique-emailservice:$IMAGE_TAG
            - kubectl set image deployment/checkoutservice server=$ECR_REGISTRY/online-boutique-checkoutservice:$IMAGE_TAG
            - kubectl set image deployment/recommendationservice server=$ECR_REGISTRY/online-boutique-recommendationservice:$IMAGE_TAG
            - kubectl set image deployment/adservice server=$ECR_REGISTRY/online-boutique-adservice:$IMAGE_TAG
            - kubectl set image deployment/loadgenerator main=$ECR_REGISTRY/online-boutique-loadgenerator:$IMAGE_TAG
            - echo Waiting for rollouts to complete...
            - kubectl rollout status deployment/frontend --timeout=5m
            - kubectl rollout status deployment/cartservice --timeout=5m
            - kubectl rollout status deployment/productcatalogservice --timeout=5m
            - echo Deployment complete!
    EOT
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/online-boutique-microservices"
      stream_name = "build"
    }
  }

  tags = {
    Environment = "demo"
    Application = "online-boutique"
  }
}

# Data source for current AWS account
data "aws_caller_identity" "current" {}

# Output the CodeBuild project name
output "codebuild_project_name" {
  description = "CodeBuild project name for building all microservices"
  value       = aws_codebuild_project.microservices_build.name
}

output "ecr_repository_urls" {
  description = "ECR repository URLs for all microservices"
  value = {
    frontend                 = aws_ecr_repository.frontend.repository_url
    cartservice             = aws_ecr_repository.cartservice.repository_url
    productcatalogservice   = aws_ecr_repository.productcatalogservice.repository_url
    currencyservice         = aws_ecr_repository.currencyservice.repository_url
    paymentservice          = aws_ecr_repository.paymentservice.repository_url
    shippingservice         = aws_ecr_repository.shippingservice.repository_url
    emailservice            = aws_ecr_repository.emailservice.repository_url
    checkoutservice         = aws_ecr_repository.checkoutservice.repository_url
    recommendationservice   = aws_ecr_repository.recommendationservice.repository_url
    adservice               = aws_ecr_repository.adservice.repository_url
    loadgenerator           = aws_ecr_repository.loadgenerator.repository_url
  }
}
