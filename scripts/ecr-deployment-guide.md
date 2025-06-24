# Hummingbot Gateway ECR Deployment Guide

This guide will walk you through deploying the Hummingbot Gateway Docker image to Amazon Elastic Container Registry (ECR).

## Prerequisites

Before you begin, ensure you have the following installed and configured:

### 1. AWS CLI
```bash
# Install AWS CLI
curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
unzip awscliv2.zip
sudo ./aws/install

# Or on macOS with Homebrew
brew install awscli
```

### 2. Docker
```bash
# Install Docker Desktop or Docker Engine
# Visit https://docs.docker.com/get-docker/ for installation instructions
```

### 3. AWS Credentials
Configure your AWS credentials using one of these methods:

**Option A: AWS CLI Configuration**
```bash
aws configure
# Enter your AWS Access Key ID, Secret Access Key, default region, and output format
```

**Option B: Environment Variables**
```bash
export AWS_ACCESS_KEY_ID=your_access_key
export AWS_SECRET_ACCESS_KEY=your_secret_key
export AWS_DEFAULT_REGION=us-east-1
```

**Option C: IAM Role (for EC2 instances)**
- Attach an IAM role with ECR permissions to your EC2 instance

### 4. Required IAM Permissions
Your AWS user/role needs the following permissions:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "ecr:CreateRepository",
                "ecr:DescribeRepositories",
                "ecr:GetAuthorizationToken",
                "ecr:GetDownloadUrlForLayer",
                "ecr:BatchGetImage",
                "ecr:BatchCheckLayerAvailability",
                "ecr:PutImage",
                "ecr:InitiateLayerUpload",
                "ecr:UploadLayerPart",
                "ecr:CompleteLayerUpload"
            ],
            "Resource": "*"
        }
    ]
}
```

## Quick Deployment

### Using the Automated Script

1. **Make the script executable:**
```bash
chmod +x scripts/deploy-ecr.sh
```

2. **Run the deployment script:**
```bash
# Basic deployment with defaults
./scripts/deploy-ecr.sh

# Custom deployment
./scripts/deploy-ecr.sh \
  --region us-west-2 \
  --repository my-gateway \
  --tag v1.0.0
```

### Manual Deployment Steps

If you prefer to run the commands manually:

1. **Set your variables:**
```bash
AWS_REGION="us-east-1"
ECR_REPOSITORY_NAME="hummingbot-gateway"
IMAGE_TAG="latest"
AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
```

2. **Create ECR repository:**
```bash
aws ecr create-repository \
  --repository-name $ECR_REPOSITORY_NAME \
  --region $AWS_REGION \
  --image-scanning-configuration scanOnPush=true \
  --encryption-configuration encryptionType=AES256
```

3. **Get ECR login token:**
```bash
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
```

4. **Build the Docker image:**
```bash
docker build \
  --build-arg BRANCH=$(git rev-parse --abbrev-ref HEAD) \
  --build-arg COMMIT=$(git rev-parse HEAD) \
  --build-arg BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ') \
  -t $ECR_REPOSITORY_NAME:$IMAGE_TAG .
```

5. **Tag the image for ECR:**
```bash
docker tag $ECR_REPOSITORY_NAME:$IMAGE_TAG \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY_NAME:$IMAGE_TAG
```

6. **Push to ECR:**
```bash
docker push $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY_NAME:$IMAGE_TAG
```

## Running the Deployed Image

### Pull and Run Locally
```bash
# Pull the image
docker pull $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY_NAME:$IMAGE_TAG

# Run the container
docker run -d \
  --name hummingbot-gateway \
  -p 15888:15888 \
  -v $(pwd)/conf:/home/gateway/conf \
  -v $(pwd)/logs:/home/gateway/logs \
  -v $(pwd)/db:/home/gateway/db \
  -v $(pwd)/certs:/home/gateway/certs \
  $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY_NAME:$IMAGE_TAG
```

### Deploy to ECS/Fargate

Create a `task-definition.json`:
```json
{
  "family": "hummingbot-gateway",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "executionRoleArn": "arn:aws:iam::YOUR_ACCOUNT_ID:role/ecsTaskExecutionRole",
  "containerDefinitions": [
    {
      "name": "gateway",
      "image": "YOUR_ACCOUNT_ID.dkr.ecr.YOUR_REGION.amazonaws.com/hummingbot-gateway:latest",
      "portMappings": [
        {
          "containerPort": 15888,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {
          "name": "NODE_ENV",
          "value": "production"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/hummingbot-gateway",
          "awslogs-region": "YOUR_REGION",
          "awslogs-stream-prefix": "ecs"
        }
      }
    }
  ]
}
```

Register and run the task:
```bash
# Register task definition
aws ecs register-task-definition --cli-input-json file://task-definition.json

# Run the task
aws ecs run-task \
  --cluster your-cluster-name \
  --task-definition hummingbot-gateway \
  --launch-type FARGATE \
  --network-configuration "awsvpcConfiguration={subnets=[subnet-12345],securityGroups=[sg-12345],assignPublicIp=ENABLED}"
```

### Deploy to Kubernetes

Create a `deployment.yaml`:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hummingbot-gateway
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hummingbot-gateway
  template:
    metadata:
      labels:
        app: hummingbot-gateway
    spec:
      containers:
      - name: gateway
        image: YOUR_ACCOUNT_ID.dkr.ecr.YOUR_REGION.amazonaws.com/hummingbot-gateway:latest
        ports:
        - containerPort: 15888
        env:
        - name: NODE_ENV
          value: "production"
        volumeMounts:
        - name: config
          mountPath: /home/gateway/conf
        - name: logs
          mountPath: /home/gateway/logs
        - name: db
          mountPath: /home/gateway/db
        - name: certs
          mountPath: /home/gateway/certs
      volumes:
      - name: config
        emptyDir: {}
      - name: logs
        emptyDir: {}
      - name: db
        emptyDir: {}
      - name: certs
        emptyDir: {}
---
apiVersion: v1
kind: Service
metadata:
  name: hummingbot-gateway-service
spec:
  selector:
    app: hummingbot-gateway
  ports:
  - protocol: TCP
    port: 15888
    targetPort: 15888
  type: LoadBalancer
```

Apply the deployment:
```bash
kubectl apply -f deployment.yaml
```

## Configuration

### Environment Variables
The Gateway container supports the following environment variables:

- `NODE_ENV`: Environment (production, development)
- `DEV`: Enable development mode (true/false)
- `PORT`: Server port (default: 15888)

### Volume Mounts
The container expects these volume mounts:
- `/home/gateway/conf`: Configuration files
- `/home/gateway/logs`: Log files
- `/home/gateway/db`: Database files
- `/home/gateway/certs`: Certificate files

## Troubleshooting

### Common Issues

1. **Authentication Errors**
```bash
# Re-authenticate with ECR
aws ecr get-login-password --region $AWS_REGION | \
  docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com
```

2. **Repository Not Found**
```bash
# Check if repository exists
aws ecr describe-repositories --repository-names $ECR_REPOSITORY_NAME --region $AWS_REGION

# Create if it doesn't exist
aws ecr create-repository --repository-name $ECR_REPOSITORY_NAME --region $AWS_REGION
```

3. **Permission Denied**
- Ensure your AWS credentials have the required ECR permissions
- Check if you're using the correct AWS profile: `export AWS_PROFILE=your-profile`

4. **Docker Build Failures**
```bash
# Clean Docker cache
docker system prune -a

# Rebuild without cache
docker build --no-cache -t $ECR_REPOSITORY_NAME:$IMAGE_TAG .
```

### Logs and Debugging

1. **View container logs:**
```bash
docker logs hummingbot-gateway
```

2. **Access container shell:**
```bash
docker exec -it hummingbot-gateway /bin/bash
```

3. **Check ECR repository:**
```bash
aws ecr describe-images --repository-name $ECR_REPOSITORY_NAME --region $AWS_REGION
```

## Security Best Practices

1. **Use IAM Roles instead of Access Keys** when possible
2. **Enable ECR image scanning** for vulnerability detection
3. **Use specific image tags** instead of `latest` in production
4. **Implement image lifecycle policies** to manage storage costs
5. **Use private subnets** for ECS tasks in production
6. **Enable VPC Flow Logs** for network monitoring

## Cost Optimization

1. **Set up ECR lifecycle policies** to automatically delete old images
2. **Use multi-stage builds** to reduce image size
3. **Consider using ECR Public** for public images
4. **Monitor ECR storage costs** in AWS Cost Explorer

## Next Steps

After successful deployment:

1. Set up monitoring and alerting
2. Configure CI/CD pipelines for automated deployments
3. Implement health checks and auto-scaling
4. Set up backup and disaster recovery procedures
5. Document your deployment process for your team

For more information, refer to:
- [AWS ECR Documentation](https://docs.aws.amazon.com/ecr/)
- [Hummingbot Gateway Documentation](https://hummingbot.org/gateway/)
- [Docker Best Practices](https://docs.docker.com/develop/dev-best-practices/) 