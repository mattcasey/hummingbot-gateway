#!/bin/bash

# ECR Lifecycle Policy Setup Script
# This script sets up lifecycle policies for ECR repositories to manage storage costs

set -e

# Configuration
AWS_REGION=${AWS_REGION:-"us-east-1"}
ECR_REPOSITORY_NAME=${ECR_REPOSITORY_NAME:-"hummingbot-gateway"}
LIFECYCLE_POLICY_FILE="scripts/ecr-lifecycle-policy.json"

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

# Function to check if AWS CLI is installed
check_aws_cli() {
    if ! command -v aws &> /dev/null; then
        print_error "AWS CLI is not installed. Please install it first."
        exit 1
    fi
}

# Function to check if repository exists
check_repository() {
    print_status "Checking if ECR repository exists..."
    if ! aws ecr describe-repositories --repository-names "$ECR_REPOSITORY_NAME" --region "$AWS_REGION" &> /dev/null; then
        print_error "ECR repository '$ECR_REPOSITORY_NAME' does not exist in region '$AWS_REGION'"
        print_status "Please create the repository first using the deploy script or manually"
        exit 1
    fi
    print_success "ECR repository found"
}

# Function to set lifecycle policy
set_lifecycle_policy() {
    print_status "Setting lifecycle policy for repository: $ECR_REPOSITORY_NAME"
    
    if [ ! -f "$LIFECYCLE_POLICY_FILE" ]; then
        print_error "Lifecycle policy file not found: $LIFECYCLE_POLICY_FILE"
        exit 1
    fi
    
    aws ecr put-lifecycle-policy \
        --repository-name "$ECR_REPOSITORY_NAME" \
        --region "$AWS_REGION" \
        --lifecycle-policy-text "file://$LIFECYCLE_POLICY_FILE"
    
    print_success "Lifecycle policy set successfully"
}

# Function to show current lifecycle policy
show_lifecycle_policy() {
    print_status "Current lifecycle policy for repository: $ECR_REPOSITORY_NAME"
    
    if aws ecr get-lifecycle-policy --repository-name "$ECR_REPOSITORY_NAME" --region "$AWS_REGION" &> /dev/null; then
        aws ecr get-lifecycle-policy --repository-name "$ECR_REPOSITORY_NAME" --region "$AWS_REGION" --output json | jq .
    else
        print_warning "No lifecycle policy found for this repository"
    fi
}

# Function to delete lifecycle policy
delete_lifecycle_policy() {
    print_status "Deleting lifecycle policy for repository: $ECR_REPOSITORY_NAME"
    
    if aws ecr delete-lifecycle-policy --repository-name "$ECR_REPOSITORY_NAME" --region "$AWS_REGION" &> /dev/null; then
        print_success "Lifecycle policy deleted successfully"
    else
        print_warning "No lifecycle policy found to delete"
    fi
}

# Function to show repository info
show_repository_info() {
    print_status "Repository information:"
    aws ecr describe-repositories --repository-names "$ECR_REPOSITORY_NAME" --region "$AWS_REGION" --output table
}

# Function to show image count
show_image_count() {
    print_status "Image count in repository:"
    local image_count=$(aws ecr describe-images --repository-name "$ECR_REPOSITORY_NAME" --region "$AWS_REGION" --query 'imageDetails | length(@)' --output text)
    echo "Total images: $image_count"
}

# Main execution
main() {
    print_status "Starting ECR lifecycle policy setup..."
    
    # Pre-flight checks
    check_aws_cli
    check_repository
    
    # Set lifecycle policy
    set_lifecycle_policy
    
    # Show results
    echo ""
    show_lifecycle_policy
    echo ""
    show_image_count
    
    print_success "ECR lifecycle policy setup completed!"
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
        --show)
            check_aws_cli
            check_repository
            show_lifecycle_policy
            show_image_count
            exit 0
            ;;
        --delete)
            check_aws_cli
            check_repository
            delete_lifecycle_policy
            exit 0
            ;;
        --info)
            check_aws_cli
            check_repository
            show_repository_info
            exit 0
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
            echo "  --region REGION        AWS region (default: us-east-1)"
            echo "  --repository NAME      ECR repository name (default: hummingbot-gateway)"
            echo "  --show                 Show current lifecycle policy"
            echo "  --delete               Delete lifecycle policy"
            echo "  --info                 Show repository information"
            echo "  --help                 Show this help message"
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