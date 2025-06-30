#!/bin/bash

# Hummingbot Gateway ECR Deployment Script
# This script builds and deploys the Gateway Docker image to Amazon ECR

set -e

# Configuration
AWS_REGION=${AWS_REGION:-"us-east-1"}
ECR_REPOSITORY_NAME=${ECR_REPOSITORY_NAME:-"hummingbot-gateway"}
IMAGE_TAG=${IMAGE_TAG:-"latest"}
AWS_ACCOUNT_ID=${AWS_ACCOUNT_ID:-""}
PLATFORM=${PLATFORM:-""}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to detect platform
detect_platform() {
    local arch=$(uname -m)
    local os=$(uname -s)
    
    if [ "$os" = "Darwin" ]; then
        if [ "$arch" = "arm64" ]; then
            PLATFORM="linux/amd64"
            print_status "Detected Apple Silicon Mac (ARM64), building for linux/amd64"
        else
            PLATFORM="linux/amd64"
            print_status "Detected Intel Mac, building for linux/amd64"
        fi
    elif [ "$os" = "Linux" ]; then
        if [ "$arch" = "x86_64" ]; then
            PLATFORM="linux/amd64"
            print_status "Detected Linux x86_64, building for linux/amd64"
        elif [ "$arch" = "aarch64" ]; then
            PLATFORM="linux/arm64"
            print_status "Detected Linux ARM64, building for linux/arm64"
        else
            PLATFORM="linux/amd64"
            print_warning "Unknown Linux architecture, defaulting to linux/amd64"
        fi
    else
        PLATFORM="linux/amd64"
        print_warning "Unknown OS, defaulting to linux/amd64"
    fi
}

# Function to check if AWS CLI is installed
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
}

# Function to check if Docker is running
check_docker() {
    if ! docker info &> /dev/null; then
        print_error "Docker is not running. Please start Docker first."
        exit 1
    fi
}

# Function to check Docker buildx support
check_buildx() {
    if ! docker buildx version &> /dev/null; then
        print_warning "Docker buildx not available, using standard docker build"
        USE_BUILDX=false
    else
        print_status "Docker buildx available"
        USE_BUILDX=true
    fi
}

# Function to get AWS account ID if not provided
get_aws_account_id() {
    if [ -z "$AWS_ACCOUNT_ID" ]; then
        print_status "Getting AWS account ID..."
        AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
        if [ $? -ne 0 ]; then
            print_error "Failed to get AWS account ID. Please check your AWS credentials."
            exit 1
        fi
        print_success "AWS Account ID: $AWS_ACCOUNT_ID"
    fi
}

# Function to create ECR repository if it doesn't exist
create_ecr_repository() {
    print_status "Checking if ECR repository exists..."
    if ! aws ecr describe-repositories --repository-names "$ECR_REPOSITORY_NAME" --region "$AWS_REGION" &> /dev/null; then
        print_status "Creating ECR repository: $ECR_REPOSITORY_NAME"
        aws ecr create-repository \
            --repository-name "$ECR_REPOSITORY_NAME" \
            --region "$AWS_REGION" \
            --image-scanning-configuration scanOnPush=true \
            --encryption-configuration encryptionType=AES256
        print_success "ECR repository created successfully"
    else
        print_success "ECR repository already exists"
    fi
}

# Function to get ECR login token
get_ecr_login() {
    print_status "Getting ECR login token..."
    aws ecr get-login-password --region "$AWS_REGION" | docker login --username AWS --password-stdin "$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com"
    print_success "ECR login successful"
}

# Function to build Docker image
build_image() {
    print_status "Building Docker image..."
    
    # Get git info for build args
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    
    # Build command with platform support
    if [ "$USE_BUILDX" = true ]; then
        print_status "Using Docker buildx for multi-platform support"
        docker buildx build \
            --platform "$PLATFORM" \
            --build-arg BRANCH="$BRANCH" \
            --build-arg COMMIT="$COMMIT" \
            --build-arg BUILD_DATE="$BUILD_DATE" \
            -t "$ECR_REPOSITORY_NAME:$IMAGE_TAG" \
            -t "$ECR_REPOSITORY_NAME:$COMMIT" \
            --load \
            .
    else
        print_status "Using standard Docker build"
        docker build \
            --build-arg BRANCH="$BRANCH" \
            --build-arg COMMIT="$COMMIT" \
            --build-arg BUILD_DATE="$BUILD_DATE" \
            -t "$ECR_REPOSITORY_NAME:$IMAGE_TAG" \
            -t "$ECR_REPOSITORY_NAME:$COMMIT" \
            .
    fi
    
    print_success "Docker image built successfully"
}

# Function to tag Docker image for ECR
tag_image() {
    local ecr_uri="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY_NAME"
    
    print_status "Tagging Docker image for ECR..."
    docker tag "$ECR_REPOSITORY_NAME:$IMAGE_TAG" "$ecr_uri:$IMAGE_TAG"
    docker tag "$ECR_REPOSITORY_NAME:$COMMIT" "$ecr_uri:$COMMIT"
    print_success "Docker image tagged successfully"
}

# Function to push Docker image to ECR
push_image() {
    local ecr_uri="$AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com/$ECR_REPOSITORY_NAME"
    
    print_status "Pushing Docker image to ECR..."
    docker push "$ecr_uri:$IMAGE_TAG"
    docker push "$ecr_uri:$COMMIT"
    print_success "Docker image pushed successfully"
    
    print_success "Image URI: $ecr_uri:$IMAGE_TAG"
    print_success "Commit URI: $ecr_uri:$COMMIT"
}

# Function to clean up local images
cleanup() {
    print_status "Cleaning up local Docker images..."
    docker rmi "$ECR_REPOSITORY_NAME:$IMAGE_TAG" 2>/dev/null || true
    docker rmi "$ECR_REPOSITORY_NAME:$COMMIT" 2>/dev/null || true
    print_success "Cleanup completed"
}

# Main execution
main() {
    print_status "Starting Hummingbot Gateway ECR deployment..."
    
    # Pre-flight checks
    check_aws_cli
    check_docker
    check_buildx
    
    # Detect platform
    detect_platform
    
    # Get AWS account ID
    get_aws_account_id
    
    # Create ECR repository
    create_ecr_repository
    
    # Get ECR login
    get_ecr_login
    
    # Build image
    build_image
    
    # Tag image
    tag_image
    
    # Push image
    push_image
    
    # Cleanup
    cleanup
    
    print_success "Deployment completed successfully!"
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --region)
            AWS_REGION="$2"
            shift 2
            ;;
        --repository)
            ECR_REPOSITORY_NAME="$2"
            shift 2
            ;;
        --tag)
            IMAGE_TAG="$2"
            shift 2
            ;;
        --account-id)
            AWS_ACCOUNT_ID="$2"
            shift 2
            ;;
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --region REGION        AWS region (default: us-east-1)"
            echo "  --repository NAME      ECR repository name (default: hummingbot-gateway)"
            echo "  --tag TAG             Image tag (default: latest)"
            echo "  --account-id ID       AWS account ID (will auto-detect if not provided)"
            echo "  --platform PLATFORM   Docker platform (auto-detected if not provided)"
            echo "  --help                Show this help message"
            echo ""
            echo "Supported platforms:"
            echo "  linux/amd64           For x86_64 systems"
            echo "  linux/arm64           For ARM64 systems"
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Run main function
main 