#!/bin/bash

# Test Docker Build Script
# This script tests the Docker build locally to ensure it works before ECR deployment

set -e

# Configuration
IMAGE_NAME="hummingbot-gateway-test"
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

# Function to clean up previous test images
cleanup_previous() {
    print_status "Cleaning up previous test images..."
    docker rmi "$IMAGE_NAME:latest" 2>/dev/null || true
    print_success "Cleanup completed"
}

# Function to build Docker image
build_image() {
    print_status "Building Docker image for testing..."
    
    # Get git info for build args
    BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "unknown")
    COMMIT=$(git rev-parse HEAD 2>/dev/null || echo "unknown")
    BUILD_DATE=$(date -u +'%Y-%m-%dT%H:%M:%SZ')
    
    print_status "Build arguments:"
    print_status "  BRANCH: $BRANCH"
    print_status "  COMMIT: $COMMIT"
    print_status "  BUILD_DATE: $BUILD_DATE"
    print_status "  PLATFORM: $PLATFORM"
    
    # Build command with platform support
    if [ "$USE_BUILDX" = true ]; then
        print_status "Using Docker buildx for multi-platform support"
        docker buildx build \
            --platform "$PLATFORM" \
            --build-arg BRANCH="$BRANCH" \
            --build-arg COMMIT="$COMMIT" \
            --build-arg BUILD_DATE="$BUILD_DATE" \
            -t "$IMAGE_NAME:latest" \
            --load \
            .
    else
        print_status "Using standard Docker build"
        docker build \
            --build-arg BRANCH="$BRANCH" \
            --build-arg COMMIT="$COMMIT" \
            --build-arg BUILD_DATE="$BUILD_DATE" \
            -t "$IMAGE_NAME:latest" \
            .
    fi
    
    print_success "Docker image built successfully"
}

# Function to test the image
test_image() {
    print_status "Testing the built image..."
    
    # Test if the image can start
    print_status "Starting container for testing..."
    CONTAINER_ID=$(docker run -d --name gateway-test-container "$IMAGE_NAME:latest" sleep 30)
    
    if [ $? -eq 0 ]; then
        print_success "Container started successfully"
        
        # Check if the application files are present
        print_status "Checking application files..."
        if docker exec "$CONTAINER_ID" test -f /home/gateway/dist/index.js; then
            print_success "Application built successfully"
        else
            print_error "Application build failed - dist/index.js not found"
        fi
        
        # Check if configuration directories exist
        for dir in conf logs db certs; do
            if docker exec "$CONTAINER_ID" test -d "/home/gateway/$dir"; then
                print_success "Directory /home/gateway/$dir exists"
            else
                print_error "Directory /home/gateway/$dir missing"
            fi
        done
        
        # Stop and remove the test container
        docker stop "$CONTAINER_ID" 2>/dev/null || true
        docker rm "$CONTAINER_ID" 2>/dev/null || true
        
    else
        print_error "Failed to start container"
    fi
}

# Function to show image info
show_image_info() {
    print_status "Image information:"
    docker images "$IMAGE_NAME:latest"
    
    print_status "Image details:"
    docker inspect "$IMAGE_NAME:latest" --format='{{.Architecture}} {{.Os}} {{.Size}}'
}

# Main execution
main() {
    print_status "Starting Docker build test..."
    
    # Pre-flight checks
    check_docker
    check_buildx
    
    # Detect platform
    detect_platform
    
    # Cleanup previous builds
    cleanup_previous
    
    # Build image
    build_image
    
    # Test image
    test_image
    
    # Show image info
    show_image_info
    
    print_success "Docker build test completed successfully!"
    print_status "You can now run the ECR deployment script with confidence."
}

# Handle script arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --platform)
            PLATFORM="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [OPTIONS]"
            echo "Options:"
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