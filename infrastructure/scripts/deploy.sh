#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="cluster-iac"
TERRAFORM_DIR="infrastructure/terraform"
ANSIBLE_DIR="infrastructure/ansible"

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_prerequisites() {
    log_info "Checking prerequisites..."
    
    # Check if terraform is installed
    if ! command -v terraform &> /dev/null; then
        log_error "Terraform is not installed. Please install Terraform first."
        exit 1
    fi
    
    # Check if ansible is installed
    if ! command -v ansible-playbook &> /dev/null; then
        log_error "Ansible is not installed. Please install Ansible first."
        exit 1
    fi
    
    # Check if AWS credentials are configured
    if ! command -v aws &> /dev/null; then
        log_warning "AWS CLI is not installed. Make sure you have AWS credentials configured."
    fi
    
    # Check if required files exist
    if [ ! -f "${TERRAFORM_DIR}/terraform.tfvars" ]; then
        log_error "terraform.tfvars file not found. Please copy terraform.tfvars.example and configure it."
        exit 1
    fi
    
    log_success "Prerequisites check completed"
}

deploy_infrastructure() {
    log_info "Deploying infrastructure with Terraform..."
    
    cd ${TERRAFORM_DIR}
    
    # Initialize Terraform
    log_info "Initializing Terraform..."
    terraform init
    
    # Plan deployment
    log_info "Planning Terraform deployment..."
    terraform plan -out=tfplan
    
    # Apply deployment
    log_info "Applying Terraform deployment..."
    terraform apply tfplan
    
    # Generate inventory for Ansible
    log_info "Generating Ansible inventory..."
    terraform output -json > ../ansible/terraform-output.json
    
    cd - > /dev/null
    log_success "Infrastructure deployment completed"
}

generate_ansible_inventory() {
    log_info "Generating Ansible inventory from Terraform outputs..."
    
    # Extract IPs from Terraform output
    GATEWAY_IP=$(terraform -chdir=${TERRAFORM_DIR} output -raw gateway_public_ip)
    API_SERVICES_IP=$(terraform -chdir=${TERRAFORM_DIR} output -raw api_services_public_ip)
    STORAGE_IP=$(terraform -chdir=${TERRAFORM_DIR} output -raw storage_public_ip)
    
    GATEWAY_PRIVATE_IP=$(terraform -chdir=${TERRAFORM_DIR} output -raw gateway_private_ip)
    API_SERVICES_PRIVATE_IP=$(terraform -chdir=${TERRAFORM_DIR} output -raw api_services_private_ip)
    STORAGE_PRIVATE_IP=$(terraform -chdir=${TERRAFORM_DIR} output -raw storage_private_ip)
    
    # Create dynamic inventory
    cat > ${ANSIBLE_DIR}/inventory/dynamic_hosts.yml << EOF
all:
  children:
    gateway:
      hosts:
        gateway-server:
          ansible_host: ${GATEWAY_IP}
          ansible_user: ubuntu
          ansible_ssh_private_key_file: ~/.ssh/${PROJECT_NAME}-key
          private_ip: ${GATEWAY_PRIVATE_IP}
          role: gateway
    
    api_services:
      hosts:
        api-services-server:
          ansible_host: ${API_SERVICES_IP}
          ansible_user: ubuntu
          ansible_ssh_private_key_file: ~/.ssh/${PROJECT_NAME}-key
          private_ip: ${API_SERVICES_PRIVATE_IP}
          role: api-services
    
    storage:
      hosts:
        storage-server:
          ansible_host: ${STORAGE_IP}
          ansible_user: ubuntu
          ansible_ssh_private_key_file: ~/.ssh/${PROJECT_NAME}-key
          private_ip: ${STORAGE_PRIVATE_IP}
          role: storage

  vars:
    ansible_ssh_common_args: '-o StrictHostKeyChecking=no'
    ansible_python_interpreter: /usr/bin/python3
    project_name: ${PROJECT_NAME}
EOF
    
    log_success "Ansible inventory generated"
}

wait_for_instances() {
    log_info "Waiting for instances to be ready..."
    
    # Wait for SSH to be available
    GATEWAY_IP=$(terraform -chdir=${TERRAFORM_DIR} output -raw gateway_public_ip)
    API_SERVICES_IP=$(terraform -chdir=${TERRAFORM_DIR} output -raw api_services_public_ip)
    STORAGE_IP=$(terraform -chdir=${TERRAFORM_DIR} output -raw storage_public_ip)
    
    for ip in $GATEWAY_IP $API_SERVICES_IP $STORAGE_IP; do
        log_info "Waiting for SSH on $ip..."
        while ! nc -z $ip 22; do
            sleep 5
        done
        log_success "SSH is ready on $ip"
    done
    
    # Additional wait for cloud-init to complete
    log_info "Waiting for cloud-init to complete..."
    sleep 60
}

configure_services() {
    log_info "Configuring services with Ansible..."
    
    cd ${ANSIBLE_DIR}
    
    # Run Ansible playbook
    ansible-playbook -i inventory/dynamic_hosts.yml playbooks/site.yml -v
    
    cd - > /dev/null
    log_success "Service configuration completed"
}

show_deployment_info() {
    log_info "Deployment completed successfully!"
    
    GATEWAY_IP=$(terraform -chdir=${TERRAFORM_DIR} output -raw gateway_public_ip)
    API_SERVICES_IP=$(terraform -chdir=${TERRAFORM_DIR} output -raw api_services_public_ip)
    STORAGE_IP=$(terraform -chdir=${TERRAFORM_DIR} output -raw storage_public_ip)
    
    echo ""
    echo "=== Deployment Information ==="
    echo "Gateway Server: $GATEWAY_IP"
    echo "API Services Server: $API_SERVICES_IP"
    echo "Storage Server: $STORAGE_IP"
    echo ""
    echo "=== Application URLs ==="
    echo "API Gateway: http://$GATEWAY_IP"
    echo "Health Check: http://$GATEWAY_IP/health"
    echo ""
    echo "=== SSH Commands ==="
    echo "Gateway: ssh -i ~/.ssh/${PROJECT_NAME}-key ubuntu@$GATEWAY_IP"
    echo "API Services: ssh -i ~/.ssh/${PROJECT_NAME}-key ubuntu@$API_SERVICES_IP"
    echo "Storage: ssh -i ~/.ssh/${PROJECT_NAME}-key ubuntu@$STORAGE_IP"
    echo ""
}

# Main deployment process
main() {
    log_info "Starting Cluster IAC deployment..."
    
    check_prerequisites
    deploy_infrastructure
    generate_ansible_inventory
    wait_for_instances
    configure_services
    show_deployment_info
    
    log_success "Deployment completed successfully!"
}

# Handle script arguments
case "${1:-deploy}" in
    "deploy")
        main
        ;;
    "destroy")
        log_warning "Destroying infrastructure..."
        cd ${TERRAFORM_DIR}
        terraform destroy
        cd - > /dev/null
        log_success "Infrastructure destroyed"
        ;;
    "plan")
        log_info "Planning infrastructure..."
        cd ${TERRAFORM_DIR}
        terraform plan
        cd - > /dev/null
        ;;
    "configure")
        log_info "Running configuration only..."
        generate_ansible_inventory
        configure_services
        ;;
    *)
        echo "Usage: $0 {deploy|destroy|plan|configure}"
        echo "  deploy    - Deploy complete infrastructure and configure services"
        echo "  destroy   - Destroy all infrastructure"
        echo "  plan      - Show Terraform plan"
        echo "  configure - Run Ansible configuration only"
        exit 1
        ;;
esac
