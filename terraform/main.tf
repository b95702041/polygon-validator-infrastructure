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

# Basic EC2 instance for Polygon node
resource "aws_instance" "polygon_node" {
  ami           = "ami-0c02fb55956c7d316"  # Amazon Linux 2
  instance_type = "t3.medium"
  
  tags = {
    Name = "polygon-validator-node"
  }
}