# IAM role for the EBS CSI driver controller (the aws-ebs-csi-driver add-on in
# eks.tf), linked to its service account with EKS Pod Identity.

resource "aws_iam_role" "ebs_csi" {
  name               = "${var.cluster_name}-ebs-csi"
  assume_role_policy = data.aws_iam_policy_document.pod_identity_trust.json
}

# AWS-managed policy: create, attach, snapshot, and delete EBS volumes
resource "aws_iam_role_policy_attachment" "ebs_csi" {
  role       = aws_iam_role.ebs_csi.name
  policy_arn = "arn:${data.aws_partition.current.partition}:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}
