# Cluster IAC Makefile

.PHONY: help install build test docker-build docker-up docker-down clean deploy destroy plan configure

# Default target
help: ## Show this help message
	@echo "Cluster IAC - Available commands:"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_-]+:.*?## / {printf "  %-15s %s\n", $$1, $$2}' $(MAKEFILE_LIST)

# Local Development
install: ## Install dependencies
	go mod download
	go mod tidy

build: ## Build all services
	@echo "Building services..."
	@CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -o bin/product ./cmd/product
	@CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -o bin/basket ./cmd/basket
	@CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-w -s" -o bin/gateway ./fiber-gateway
	@echo "Build completed"

test: ## Run tests
	go test -v ./...

test-coverage: ## Run tests with coverage
	go test -v -cover ./...

# Docker Development
docker-build: ## Build Docker images
	docker build -f dockerfiles/product.Dockerfile -t cluster-iac/product .
	docker build -f dockerfiles/basket.Dockerfile -t cluster-iac/basket .
	docker build -f dockerfiles/gateway.Dockerfile -t cluster-iac/gateway .

docker-up: ## Start services with Docker Compose
	docker-compose up -d

docker-down: ## Stop services
	docker-compose down

docker-logs: ## View logs
	docker-compose logs -f

docker-clean: ## Clean Docker images and containers
	docker-compose down -v
	docker system prune -f

# AWS Deployment
deploy: ## Deploy to AWS
	@chmod +x infrastructure/scripts/deploy.sh
	@./infrastructure/scripts/deploy.sh deploy

destroy: ## Destroy AWS infrastructure
	@chmod +x infrastructure/scripts/deploy.sh
	@./infrastructure/scripts/deploy.sh destroy

plan: ## Show Terraform plan
	@chmod +x infrastructure/scripts/deploy.sh
	@./infrastructure/scripts/deploy.sh plan

configure: ## Run Ansible configuration only
	@chmod +x infrastructure/scripts/deploy.sh
	@./infrastructure/scripts/deploy.sh configure

# Terraform specific commands
tf-init: ## Initialize Terraform
	cd infrastructure/terraform && terraform init

tf-plan: ## Run Terraform plan
	cd infrastructure/terraform && terraform plan

tf-apply: ## Apply Terraform changes
	cd infrastructure/terraform && terraform apply

tf-output: ## Show Terraform outputs
	cd infrastructure/terraform && terraform output

# Ansible specific commands
ansible-ping: ## Ping all servers
	cd infrastructure/ansible && ansible all -i inventory/dynamic_hosts.yml -m ping

ansible-deploy: ## Run Ansible deployment
	cd infrastructure/ansible && ansible-playbook -i inventory/dynamic_hosts.yml playbooks/site.yml

ansible-check: ## Run Ansible in check mode
	cd infrastructure/ansible && ansible-playbook -i inventory/dynamic_hosts.yml playbooks/site.yml --check

# Health checks
health-check: ## Check service health
	@echo "Checking local services..."
	@curl -f http://localhost:8082/health || echo "Gateway not responding"
	@curl -f http://localhost:8080/health || echo "Product service not responding"
	@curl -f http://localhost:8081/health || echo "Basket service not responding"

health-check-aws: ## Check AWS deployed services health
	@if [ -f infrastructure/terraform/terraform.tfstate ]; then \
		GATEWAY_IP=$$(cd infrastructure/terraform && terraform output -raw gateway_public_ip); \
		echo "Checking AWS services at $$GATEWAY_IP..."; \
		curl -f http://$$GATEWAY_IP/health || echo "AWS Gateway not responding"; \
	else \
		echo "No Terraform state found. Deploy first."; \
	fi

# Clean up
clean: ## Clean build artifacts
	rm -rf bin/
	rm -rf infrastructure/ansible/reports/
	rm -f infrastructure/ansible/terraform-output.json
	rm -f infrastructure/ansible/inventory/dynamic_hosts.yml

clean-all: clean docker-clean ## Clean everything including Docker

# Setup
setup-aws: ## Setup AWS development environment
	@echo "Setting up AWS environment..."
	@if [ ! -f infrastructure/terraform/terraform.tfvars ]; then \
		cp infrastructure/terraform/terraform.tfvars.example infrastructure/terraform/terraform.tfvars; \
		echo "Created terraform.tfvars from example. Please edit it with your values."; \
	fi
	@echo "Make sure to:"
	@echo "1. Configure AWS credentials (aws configure)"
	@echo "2. Edit infrastructure/terraform/terraform.tfvars"
	@echo "3. Generate SSH key pair if needed"

generate-key: ## Generate SSH key pair for AWS
	@if [ ! -f ~/.ssh/cluster-iac-key ]; then \
		ssh-keygen -t rsa -b 4096 -f ~/.ssh/cluster-iac-key -N ""; \
		echo "SSH key generated at ~/.ssh/cluster-iac-key"; \
		echo "Add this public key to terraform.tfvars:"; \
		cat ~/.ssh/cluster-iac-key.pub; \
	else \
		echo "SSH key already exists at ~/.ssh/cluster-iac-key"; \
	fi

# Monitoring
logs-local: ## View local logs
	tail -f /tmp/*.log

logs-aws: ## View AWS logs (requires SSH access)
	@GATEWAY_IP=$$(cd infrastructure/terraform && terraform output -raw gateway_public_ip 2>/dev/null || echo ""); \
	if [ -n "$$GATEWAY_IP" ]; then \
		ssh -i ~/.ssh/cluster-iac-key ubuntu@$$GATEWAY_IP "sudo tail -f /var/log/cluster-iac/*.log"; \
	else \
		echo "No AWS deployment found"; \
	fi

# Database operations
db-backup: ## Backup database (AWS)
	@STORAGE_IP=$$(cd infrastructure/terraform && terraform output -raw storage_public_ip 2>/dev/null || echo ""); \
	if [ -n "$$STORAGE_IP" ]; then \
		ssh -i ~/.ssh/cluster-iac-key ubuntu@$$STORAGE_IP "/usr/local/bin/postgres-backup.sh"; \
	else \
		echo "No AWS deployment found"; \
	fi

# Development shortcuts
dev-up: docker-up health-check ## Start development environment
dev-down: docker-down ## Stop development environment
dev-restart: docker-down docker-up ## Restart development environment

# Production shortcuts
prod-deploy: setup-aws deploy health-check-aws ## Full production deployment
prod-update: configure health-check-aws ## Update production deployment
