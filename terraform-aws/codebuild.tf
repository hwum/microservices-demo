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

# ECR Repository for frontend
resource "aws_ecr_repository" "frontend" {
  name                 = "online-boutique-frontend"
  image_tag_mutability = "MUTABLE"

  image_scanning_configuration {
    scan_on_push = false
  }
}

# CodeBuild Project
resource "aws_codebuild_project" "frontend_build" {
  name          = "online-boutique-frontend-build"
  description   = "Build and deploy custom frontend with footer changes"
  build_timeout = "30"
  service_role  = aws_iam_role.codebuild_role.arn

  artifacts {
    type = "NO_ARTIFACTS"
  }

  environment {
    compute_type                = "BUILD_GENERAL1_SMALL"
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
      name  = "IMAGE_REPO_NAME"
      value = aws_ecr_repository.frontend.name
    }

    environment_variable {
      name  = "IMAGE_TAG"
      value = "latest"
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
            - aws ecr get-login-password --region $AWS_DEFAULT_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com
            - REPOSITORY_URI=$AWS_ACCOUNT_ID.dkr.ecr.$AWS_DEFAULT_REGION.amazonaws.com/$IMAGE_REPO_NAME
            - COMMIT_HASH=$(echo $CODEBUILD_RESOLVED_SOURCE_VERSION | cut -c 1-7)
            - IMAGE_TAG_COMMIT=$${COMMIT_HASH:=latest}
        build:
          commands:
            - echo Build started on `date`
            - echo Building the Docker image...
            - |
              cat > Dockerfile.custom <<'EOF'
              FROM golang:1.25.4-alpine AS builder
              WORKDIR /src
              ENV GOPROXY=https://proxy.golang.org,direct
              ENV GOPRIVATE=""
              ENV GOSUMDB=sum.golang.org
              COPY go.mod go.sum ./
              RUN go mod download
              COPY . .
              RUN CGO_ENABLED=0 go build -ldflags="-s -w" -o /go/bin/frontend .
              FROM gcr.io/distroless/static
              WORKDIR /src
              COPY --from=builder /go/bin/frontend /src/server
              COPY ./templates ./templates
              COPY ./static ./static
              ENV GOTRACEBACK=single
              EXPOSE 8080
              ENTRYPOINT ["/src/server"]
              EOF
            - docker build -f Dockerfile.custom -t $REPOSITORY_URI:latest -t $REPOSITORY_URI:$IMAGE_TAG_COMMIT .
        post_build:
          commands:
            - echo Build completed on `date`
            - echo Pushing the Docker images...
            - docker push $REPOSITORY_URI:latest
            - docker push $REPOSITORY_URI:$IMAGE_TAG_COMMIT
            - echo Updating Kubernetes deployment...
            - aws eks update-kubeconfig --region $AWS_DEFAULT_REGION --name $EKS_CLUSTER_NAME
            - kubectl set image deployment/frontend server=$REPOSITORY_URI:$IMAGE_TAG_COMMIT
            - kubectl rollout status deployment/frontend --timeout=5m
            - echo Deployment complete!
    EOT
  }

  logs_config {
    cloudwatch_logs {
      group_name  = "/aws/codebuild/online-boutique-frontend"
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
  description = "CodeBuild project name for building frontend"
  value       = aws_codebuild_project.frontend_build.name
}

output "ecr_repository_url" {
  description = "ECR repository URL for frontend images"
  value       = aws_ecr_repository.frontend.repository_url
}
