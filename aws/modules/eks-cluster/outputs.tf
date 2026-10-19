output "region" {
  value = data.aws_region.current.region
}

output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "vpc_id" {
  value = module.vpc.vpc_id
}

output "vpc_cidr" {
  value = module.vpc.vpc_cidr_block
}

output "private_subnets" {
  value = module.vpc.private_subnets
}

output "availability_zones" {
  value = local.azs
}

output "configure_kubectl" {
  description = "Command to add the cluster to your kubeconfig"
  value       = "aws eks update-kubeconfig --region ${data.aws_region.current.region} --name ${module.eks.cluster_name}"
}

output "external_secrets_role_arn" {
  description = "IAM role the External Secrets Operator assumes through Pod Identity"
  value       = one(aws_iam_role.external_secrets[*].arn)
}

output "vault_kms_key_alias" {
  description = "KMS key alias for Vault auto-unseal; set as global.awsKms.keyId in kubernetes/vault"
  value       = one(aws_kms_alias.vault_unseal[*].name)
}

output "vault_role_arn" {
  description = "IAM role Vault assumes through Pod Identity"
  value       = one(aws_iam_role.vault[*].arn)
}
