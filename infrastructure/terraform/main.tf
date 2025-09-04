terraform {
  required_version = ">= 1.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Data sources
data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# VPC and Networking
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags = {
    Name        = "${var.project_name}-vpc"
    Environment = var.environment
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name        = "${var.project_name}-igw"
    Environment = var.environment
  }
}

resource "aws_subnet" "public" {
  count                   = length(var.availability_zones)
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidrs[count.index]
  availability_zone       = var.availability_zones[count.index]
  map_public_ip_on_launch = true

  tags = {
    Name        = "${var.project_name}-public-subnet-${count.index + 1}"
    Environment = var.environment
    Type        = "Public"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name        = "${var.project_name}-public-rt"
    Environment = var.environment
  }
}

resource "aws_route_table_association" "public" {
  count          = length(aws_subnet.public)
  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# Security Groups
resource "aws_security_group" "gateway" {
  name_description = "${var.project_name}-gateway-sg"
  description      = "Security group for API Gateway"
  vpc_id           = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }

  ingress {
    from_port   = 8082
    to_port     = 8082
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "API Gateway"
  }

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTP"
  }

  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "HTTPS"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-gateway-sg"
    Environment = var.environment
  }
}

resource "aws_security_group" "api_services" {
  name_description = "${var.project_name}-api-services-sg"
  description      = "Security group for API Services (Product & Basket)"
  vpc_id           = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }

  ingress {
    from_port       = 8080
    to_port         = 8081
    protocol        = "tcp"
    security_groups = [aws_security_group.gateway.id]
    description     = "API Services from Gateway"
  }

  ingress {
    from_port = 50051
    to_port   = 50051
    protocol  = "tcp"
    self      = true
    description = "gRPC internal communication"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-api-services-sg"
    Environment = var.environment
  }
}

resource "aws_security_group" "storage" {
  name_description = "${var.project_name}-storage-sg"
  description      = "Security group for Storage layer (PostgreSQL & Redis)"
  vpc_id           = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH"
  }

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.api_services.id]
    description     = "PostgreSQL from API Services"
  }

  ingress {
    from_port       = 6379
    to_port         = 6379
    protocol        = "tcp"
    security_groups = [aws_security_group.api_services.id]
    description     = "Redis from API Services"
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "All outbound traffic"
  }

  tags = {
    Name        = "${var.project_name}-storage-sg"
    Environment = var.environment
  }
}

# Key Pair
resource "aws_key_pair" "main" {
  key_name   = "${var.project_name}-key"
  public_key = var.public_key

  tags = {
    Name        = "${var.project_name}-key"
    Environment = var.environment
  }
}

# EC2 Instances
resource "aws_instance" "gateway" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_types.gateway
  key_name               = aws_key_pair.main.key_name
  vpc_security_group_ids = [aws_security_group.gateway.id]
  subnet_id              = aws_subnet.public[0].id

  root_block_device {
    volume_type = "gp3"
    volume_size = 20
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/user-data/gateway.sh", {
    api_services_private_ip = aws_instance.api_services.private_ip
  }))

  tags = {
    Name        = "${var.project_name}-gateway"
    Environment = var.environment
    Role        = "gateway"
  }
}

resource "aws_instance" "api_services" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_types.api_services
  key_name               = aws_key_pair.main.key_name
  vpc_security_group_ids = [aws_security_group.api_services.id]
  subnet_id              = aws_subnet.public[1].id

  root_block_device {
    volume_type = "gp3"
    volume_size = 30
    encrypted   = true
  }

  user_data = base64encode(templatefile("${path.module}/user-data/api-services.sh", {
    storage_private_ip = aws_instance.storage.private_ip
  }))

  tags = {
    Name        = "${var.project_name}-api-services"
    Environment = var.environment
    Role        = "api-services"
  }
}

resource "aws_instance" "storage" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_types.storage
  key_name               = aws_key_pair.main.key_name
  vpc_security_group_ids = [aws_security_group.storage.id]
  subnet_id              = aws_subnet.public[2].id

  root_block_device {
    volume_type = "gp3"
    volume_size = 50
    encrypted   = true
  }

  # Additional EBS volume for database storage
  ebs_block_device {
    device_name = "/dev/sdf"
    volume_type = "gp3"
    volume_size = 100
    encrypted   = true
  }

  user_data = base64encode(file("${path.module}/user-data/storage.sh"))

  tags = {
    Name        = "${var.project_name}-storage"
    Environment = var.environment
    Role        = "storage"
  }
}

# Elastic IPs
resource "aws_eip" "gateway" {
  instance = aws_instance.gateway.id
  domain   = "vpc"

  tags = {
    Name        = "${var.project_name}-gateway-eip"
    Environment = var.environment
  }
}

resource "aws_eip" "api_services" {
  instance = aws_instance.api_services.id
  domain   = "vpc"

  tags = {
    Name        = "${var.project_name}-api-services-eip"
    Environment = var.environment
  }
}

resource "aws_eip" "storage" {
  instance = aws_instance.storage.id
  domain   = "vpc"

  tags = {
    Name        = "${var.project_name}-storage-eip"
    Environment = var.environment
  }
}
