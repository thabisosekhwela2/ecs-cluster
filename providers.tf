provider "aws" {
  region = var.aws_region

  # Add retry configuration for API calls
  retry_mode = "adaptive"

  # Increase max retry attempts
  max_retries = 10

  # Add default tags
  default_tags {
    tags = var.common_tags
  }
}

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
} 