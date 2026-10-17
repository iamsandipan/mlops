variable "cluster_name" {
  description = "Name of the EKS cluster; also used to name the VPC and for Karpenter discovery tags. Make it unique per region, since IAM roles are global"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC. Use non-overlapping ranges across regions so the VPCs can be peered later"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS control plane"
  type        = string
  default     = "1.34"
}

variable "single_nat_gateway" {
  description = "Use one shared NAT gateway instead of one per AZ (cheaper, but an AZ outage cuts egress for all subnets)"
  type        = bool
  default     = false
}

variable "node_instance_types" {
  description = "Instance types for the managed node group"
  type        = list(string)
  default     = ["m6i.large"]
}

variable "node_min_size" {
  type    = number
  default = 2
}

variable "node_max_size" {
  type    = number
  default = 5
}

variable "node_desired_size" {
  type    = number
  default = 3
}
