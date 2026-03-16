terraform {
  backend "s3" {
    bucket         = "dame-terraform-state"
    key            = "openclaw/teams-alb/terraform.tfstate"
    region         = "ap-southeast-2"
    encrypt        = true
    dynamodb_table = "dame-terraform-locks"
  }

  required_version = ">= 1.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.0"
    }
  }
}

provider "aws" {
  region  = var.aws_region
  profile = var.aws_profile

  default_tags {
    tags = {
      Project     = "OpenClaw"
      Environment = var.environment
      ManagedBy   = "Terraform"
      Component   = "Teams-Integration"
    }
  }
}

provider "kubernetes" {
  config_path = var.kubeconfig_path
}
