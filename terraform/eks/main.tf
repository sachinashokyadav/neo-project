locals {
  cluster_name = var.cluster_name
}

# Get VPC (sanity)
data "aws_vpc" "selected" {
  id = var.vpc_id
}

# EKS Cluster IAM Role
resource "aws_iam_role" "eks_cluster_role" {
  name = "${local.cluster_name}-cluster-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "eks.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "eks_cluster_attach" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
  ])
  role       = aws_iam_role.eks_cluster_role.name
  policy_arn = each.key
}

# Security group for nodes (so we can control inbound/outbound)
resource "aws_security_group" "node_sg" {
  name        = "${local.cluster_name}-nodes-sg"
  description = "Security group for EKS worker nodes"
  vpc_id      = var.vpc_id

  # Egress all so nodes can reach control plane / internet (adjust if strict)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}
# EKS Cluster
resource "aws_eks_cluster" "this" {
  name     = local.cluster_name
  role_arn = aws_iam_role.eks_cluster_role.arn

  vpc_config {
    subnet_ids              = concat(var.public_subnet_ids, var.private_subnet_ids)
    endpoint_public_access  = true
    endpoint_private_access = false
    # `cluster_security_group` created by EKS; we will reference it below
  }

  depends_on = [aws_iam_role_policy_attachment.eks_cluster_attach]
}

# Wait for cluster then create OIDC provider
resource "aws_iam_openid_connect_provider" "oidc" {
  client_id_list  = ["sts.amazonaws.com"]
  url             = aws_eks_cluster.this.identity[0].oidc[0].issuer
  thumbprint_list = [data.tls_certificate.oidc_cert.certificates[0].sha1_fingerprint]
}

data "tls_certificate" "oidc_cert" {
  # Issuer URL
  url = aws_eks_cluster.this.identity[0].oidc[0].issuer

}

resource "aws_eks_addon" "vpc_cni" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "vpc-cni"

  depends_on = [aws_eks_cluster.this]
}

resource "aws_eks_addon" "coredns" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "coredns"

  depends_on = [
    aws_eks_cluster.this,
  ]
}

resource "aws_eks_addon" "kube_proxy" {
  cluster_name = aws_eks_cluster.this.name
  addon_name   = "kube-proxy"

  depends_on = [aws_eks_cluster.this]
}

resource "aws_iam_role" "ebs_csi_role" {
  name = "${local.cluster_name}-ebs-csi-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = aws_iam_openid_connect_provider.oidc.arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(aws_iam_openid_connect_provider.oidc.url, "https://", "")}:sub" = "system:serviceaccount:kube-system:ebs-csi-controller-sa"
          }
        }
      }
    ]
  })
}


resource "aws_iam_role_policy_attachment" "ebs_csi_policy" {
  role       = aws_iam_role.ebs_csi_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEBSCSIDriverPolicy"
}

resource "aws_eks_addon" "ebs_csi" {
  cluster_name             = aws_eks_cluster.this.name
  addon_name               = "aws-ebs-csi-driver"
  service_account_role_arn = aws_iam_role.ebs_csi_role.arn

  depends_on = [
    aws_iam_role_policy_attachment.ebs_csi_policy,
    aws_eks_cluster.this
  ]
}



# Node group IAM Role for EC2 instances (managed node groups use this role)
resource "aws_iam_role" "node_role" {
  name = "${local.cluster_name}-node-role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "ec2.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}
resource "aws_iam_role_policy_attachment" "node_AmazonEKSWorkerNodePolicy" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}
resource "aws_iam_role_policy_attachment" "node_AmazonEKS_CNI_Policy" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}
resource "aws_iam_role_policy_attachment" "node_ECRReadOnly" {
  role       = aws_iam_role.node_role.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

# Fetch the cluster details to get the security group id
data "aws_eks_cluster" "eks_cluster" {
  name = aws_eks_cluster.this.name
}

# Allow nodes to reach the cluster API server
resource "aws_security_group_rule" "allow_nodes_to_api_ingress" {
  type                     = "ingress"
  from_port                = 443
  to_port                  = 443
  protocol                 = "tcp"
  security_group_id        = data.aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
  source_security_group_id = aws_security_group.node_sg.id
  description              = "Allow nodes to talk to EKS control plane"
}

# Allow control plane to reach kubelet on nodes
resource "aws_security_group_rule" "allow_api_to_nodes" {
  type                     = "ingress"
  from_port                = 10250
  to_port                  = 10250
  protocol                 = "tcp"
  security_group_id        = aws_security_group.node_sg.id
  source_security_group_id = data.aws_eks_cluster.eks_cluster.vpc_config[0].cluster_security_group_id
  description              = "Allow control plane to kubelet on nodes"
}

# Managed Node Group: frontend
resource "aws_eks_node_group" "frontend" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.cluster_name}-frontend-ng"
  node_role_arn   = aws_iam_role.node_role.arn
  subnet_ids      = var.private_subnet_ids
  ami_type        = var.node_ami_type

  scaling_config {
    desired_size = var.frontend_node_count
    min_size     = var.frontend_node_count
    max_size     = var.frontend_node_count
  }

  labels = {
    role = "frontend"
  }

  remote_access {
    # Optionally allow SSH; comment out if not needed
    ec2_ssh_key               = var.key_name
    source_security_group_ids = [aws_security_group.node_sg.id]
  }

  tags = {
    "Name" = "${local.cluster_name}-frontend-ng"
  }

  force_update_version = true
  depends_on           = [aws_security_group_rule.allow_nodes_to_api_ingress]
}

# Managed Node Group: backend
resource "aws_eks_node_group" "backend" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.cluster_name}-backend-ng"
  node_role_arn   = aws_iam_role.node_role.arn
  subnet_ids      = var.private_subnet_ids
  ami_type        = var.node_ami_type

  scaling_config {
    desired_size = var.backend_node_count
    min_size     = var.backend_node_count
    max_size     = var.backend_node_count
  }

  labels = {
    role = "backend"
  }
  remote_access {
    ec2_ssh_key               = var.key_name
    source_security_group_ids = [aws_security_group.node_sg.id]
  }

  tags = {
    "Name" = "${local.cluster_name}-backend-ng"
  }

  force_update_version = true
  depends_on           = [aws_security_group_rule.allow_nodes_to_api_ingress]
}

# Managed Node Group: database
resource "aws_eks_node_group" "database" {
  cluster_name    = aws_eks_cluster.this.name
  node_group_name = "${local.cluster_name}-database-ng"
  node_role_arn   = aws_iam_role.node_role.arn
  subnet_ids      = var.private_subnet_ids
  ami_type        = var.node_ami_type

  scaling_config {
    desired_size = var.database_node_count
    min_size     = var.database_node_count
    max_size     = var.database_node_count
  }

  labels = {
    role = "database"
  }
  remote_access {
    ec2_ssh_key               = var.key_name
    source_security_group_ids = [aws_security_group.node_sg.id]
  }

  tags = {
    "Name" = "${local.cluster_name}-database-ng"
  }

  force_update_version = true
  depends_on           = [aws_security_group_rule.allow_nodes_to_api_ingress]
}
