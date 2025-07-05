# Configure AWS Provider
terraform {
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

# Create a key pair
resource "aws_key_pair" "polygon_key" {
  key_name   = "polygon-validator-key"
  public_key = file("polygon-key.pub")
}

# Security group for SSH and Polygon ports
resource "aws_security_group" "polygon_sg" {
  name = "polygon-validator-sg"

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Heimdall P2P port
  ingress {
    from_port   = 26656
    to_port     = 26656
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Bor P2P port
  ingress {
    from_port   = 30303
    to_port     = 30303
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Heimdall RPC port (optional - for monitoring)
  ingress {
    from_port   = 26657
    to_port     = 26657
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] 
  }

  # Bor RPC port (optional - for monitoring)
  ingress {
    from_port   = 8545
    to_port     = 8545
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # All outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "polygon-validator-sg"
  }
}

# EC2 instance for Polygon node with automated installation
resource "aws_instance" "polygon_node" {
  ami                    = "ami-0440d3b780d96b29d"  # Amazon Linux 2023
  instance_type          = "t3.medium"
  key_name              = aws_key_pair.polygon_key.key_name
  vpc_security_group_ids = [aws_security_group.polygon_sg.id]
  
  # Automated installation script
  user_data = base64encode(file("${path.module}/install-polygon.sh"))
  
  # Increase root volume size for builds, blockchain data, and growth
  root_block_device {
    volume_size = 80  # 80GB for builds, blockchain data, and growth
    volume_type = "gp3"
    encrypted   = true
    delete_on_termination = true
  }
  
  tags = {
    Name = "polygon-validator-node"
  }
}

# Output the public IP
output "polygon_node_ip" {
  value = aws_instance.polygon_node.public_ip
  description = "Public IP address of the Polygon node"
}