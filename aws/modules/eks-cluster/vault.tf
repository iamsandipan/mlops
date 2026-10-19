# KMS key that auto-unseals Vault (kubernetes/vault), and the IAM role Vault uses
# to call KMS, linked to its service account with EKS Pod Identity.

resource "aws_kms_key" "vault_unseal" {
  count = var.enable_vault ? 1 : 0

  description = "Vault auto-unseal for ${var.cluster_name}"
  # Old key material is kept, so Vault can still unseal after a rotation
  enable_key_rotation = true
  # Losing this key makes Vault's data unrecoverable; the window allows undoing a delete
  deletion_window_in_days = 30
}

resource "aws_kms_alias" "vault_unseal" {
  count = var.enable_vault ? 1 : 0

  # Matches global.awsKms.keyId in kubernetes/vault/values.yaml
  name          = "alias/vault-unseal-${var.cluster_name}"
  target_key_id = aws_kms_key.vault_unseal[0].key_id
}

data "aws_iam_policy_document" "vault" {
  count = var.enable_vault ? 1 : 0

  statement {
    sid       = "AutoUnseal"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:DescribeKey"]
    resources = [aws_kms_key.vault_unseal[0].arn]
  }
}

resource "aws_iam_role" "vault" {
  count = var.enable_vault ? 1 : 0

  name               = "${var.cluster_name}-vault"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy" "vault" {
  count = var.enable_vault ? 1 : 0

  name   = "kms-auto-unseal"
  role   = aws_iam_role.vault[0].id
  policy = data.aws_iam_policy_document.vault[0].json
}

resource "aws_eks_pod_identity_association" "vault" {
  count = var.enable_vault ? 1 : 0

  cluster_name    = module.eks.cluster_name
  namespace       = var.vault_namespace
  service_account = var.vault_service_account
  role_arn        = aws_iam_role.vault[0].arn
}
