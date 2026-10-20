# IAM role for the KEDA operator (kubernetes/keda), linked to its service account
# with EKS Pod Identity. Lets aws-sqs-queue scalers with podIdentity.provider: aws
# read queue length; workers that consume the messages need their own role.

locals {
  keda_sqs_arns = [
    for prefix in var.keda_sqs_queue_prefixes :
    "arn:${data.aws_partition.current.partition}:sqs:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:${prefix}"
  ]
}

data "aws_iam_policy_document" "keda" {
  statement {
    sid       = "ReadQueueLength"
    actions   = ["sqs:GetQueueAttributes", "sqs:GetQueueUrl"]
    resources = local.keda_sqs_arns
  }
}

resource "aws_iam_role" "keda" {
  count = var.enable_keda ? 1 : 0

  name               = "${var.cluster_name}-keda"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

resource "aws_iam_role_policy" "keda" {
  count = var.enable_keda ? 1 : 0

  name   = "read-sqs-queue-length"
  role   = aws_iam_role.keda[0].id
  policy = data.aws_iam_policy_document.keda.json
}

resource "aws_eks_pod_identity_association" "keda" {
  count = var.enable_keda ? 1 : 0

  cluster_name    = module.eks.cluster_name
  namespace       = var.keda_namespace
  service_account = "keda-operator"
  role_arn        = aws_iam_role.keda[0].arn
}
