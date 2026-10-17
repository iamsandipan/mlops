module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 21.0"

  name               = var.cluster_name
  kubernetes_version = var.kubernetes_version

  # Public API endpoint so kubectl works from your machine; restrict with
  # endpoint_public_access_cidrs, or set to false and reach it through a VPN/bastion
  endpoint_public_access = true

  # Gives the identity running terraform cluster-admin access
  enable_cluster_creator_admin_permissions = true

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.intra_subnets

  addons = {
    coredns = {}
    kube-proxy = {}
    vpc-cni = {
      before_compute = true
    }
    eks-pod-identity-agent = {
      before_compute = true
    }
  }

  # Baseline nodes spread across the 3 AZs. They run cluster add-ons and the
  # Karpenter controller; Karpenter launches extra capacity on demand.
  eks_managed_node_groups = {
    default = {
      ami_type       = "AL2023_x86_64_STANDARD"
      instance_types = var.node_instance_types

      min_size     = var.node_min_size
      max_size     = var.node_max_size
      desired_size = var.node_desired_size
    }
  }

  # Matches securityGroupSelectorTerms in kubernetes/karpenter/ec2nodeclass.yaml
  node_security_group_tags = {
    "karpenter.sh/discovery" = var.cluster_name
  }
}
