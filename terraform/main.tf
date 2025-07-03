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

# Security group for SSH access
resource "aws_security_group" "polygon_sg" {
  name = "polygon-validator-sg"

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# EC2 instance for Polygon node
resource "aws_instance" "polygon_node" {
  ami                    = "ami-0c02fb55956c7d316"
  instance_type          = "t3.medium"
  key_name              = aws_key_pair.polygon_key.key_name
  vpc_security_group_ids = [aws_security_group.polygon_sg.id]
  
  tags = {
    Name = "polygon-validator-node"
  }
}