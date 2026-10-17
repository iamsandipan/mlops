terraform {
  required_version = ">= 1.5.7"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.0"
    }
  }

  # State is local by default. For shared use, store it in S3, one key per region:
  # backend "s3" {
  #   bucket       = "<state-bucket>"
  #   key          = "mlops/eks/us-west-2.tfstate"
  #   region       = "us-east-1"
  #   use_lockfile = true
  # }
}

provider "aws" {
  region = "us-west-2"

  default_tags {
    tags = {
      Project   = "mlops"
      ManagedBy = "terraform"
    }
  }
}

module "cluster" {
  source = "../../modules/eks-cluster"

  cluster_name = "mlops-us-west-2"
  vpc_cidr     = "10.1.0.0/16"
}

output "cluster" {
  value = module.cluster
}

output "configure_kubectl" {
  value = module.cluster.configure_kubectl
}
