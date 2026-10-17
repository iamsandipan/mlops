terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }

  # State is local by default. For shared use, store it in S3:
  # backend "s3" {
  #   bucket       = "<state-bucket>"
  #   key          = "mlops/eks.tfstate"
  #   region       = "us-east-1"
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      Project   = "mlops"
      ManagedBy = "terraform"
    }
  }
}
