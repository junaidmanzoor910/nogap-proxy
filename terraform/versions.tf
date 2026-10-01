terraform {
  required_version = ">= 1.5.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  # Remote state (recommended for teams). Configure before first apply:
  # backend "s3" {
  #   bucket         = "your-tf-state-bucket"
  #   key            = "proxy-dev/terraform.tfstate"
  #   region         = "us-east-1"
  #   encrypt        = true
  #   dynamodb_table = "terraform-locks"
  # }
}

provider "aws" {
  profile = var.aws_profile
  region  = var.aws_region
}
