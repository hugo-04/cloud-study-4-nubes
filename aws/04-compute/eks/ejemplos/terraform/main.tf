terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

provider "aws" {
  region = var.region
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "entorno" {
  type = string
}

variable "version_kubernetes" {
  description = "Versión menor de Kubernetes (verifica las vigentes en EKS)."
  type        = string
}

variable "subredes_privadas" {
  type = list(string)
}

variable "cidr_api_publico" {
  description = "CIDR permitidos al endpoint público; vacío = endpoint solo privado."
  type        = list(string)
  default     = []
}

variable "clave_kms_arn" {
  description = "CMK para cifrar los Secrets de Kubernetes."
  type        = string
}

variable "rol_admin_arn" {
  description = "Rol de IAM que administrará el clúster (access entry)."
  type        = string
}

variable "rol_pedidos_arn" {
  description = "Rol de IAM que asumirá el pod de pedidos (Pod Identity)."
  type        = string
}

locals {
  nombre = "${var.entorno}-tienda"
}

# ---------- Rol del plano de control ----------
data "aws_iam_policy_document" "confianza_eks" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  name               = "${local.nombre}-cluster"
  assume_role_policy = data.aws_iam_policy_document.confianza_eks.json
}

resource "aws_iam_role_policy_attachment" "cluster" {
  role       = aws_iam_role.cluster.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

# ---------- Clúster ----------
resource "aws_eks_cluster" "este" {
  name     = local.nombre
  version  = var.version_kubernetes
  role_arn = aws_iam_role.cluster.arn

  access_config {
    authentication_mode                         = "API" # access entries, sin aws-auth
    bootstrap_cluster_creator_admin_permissions = false
  }

  vpc_config {
    subnet_ids              = var.subredes_privadas
    endpoint_private_access = true
    endpoint_public_access  = length(var.cidr_api_publico) > 0
    public_access_cidrs     = length(var.cidr_api_publico) > 0 ? var.cidr_api_publico : null
  }

  encryption_config {
    resources = ["secrets"]

    provider {
      key_arn = var.clave_kms_arn
    }
  }

  enabled_cluster_log_types = ["api", "audit", "authenticator"]

  depends_on = [aws_iam_role_policy_attachment.cluster]
}

# ---------- Acceso: access entries ----------
resource "aws_eks_access_entry" "admin" {
  cluster_name  = aws_eks_cluster.este.name
  principal_arn = var.rol_admin_arn
  type          = "STANDARD"
}

resource "aws_eks_access_policy_association" "admin" {
  cluster_name  = aws_eks_cluster.este.name
  principal_arn = aws_eks_access_entry.admin.principal_arn
  policy_arn    = "arn:aws:eks::aws:cluster-access-policy/AmazonEKSClusterAdminPolicy"

  access_scope {
    type = "cluster"
  }
}

# ---------- Nodos gestionados ----------
data "aws_iam_policy_document" "confianza_ec2" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "nodos" {
  name               = "${local.nombre}-nodos"
  assume_role_policy = data.aws_iam_policy_document.confianza_ec2.json
}

resource "aws_iam_role_policy_attachment" "nodos" {
  for_each = toset([
    "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy",
    "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy",
    "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly",
  ])

  role       = aws_iam_role.nodos.name
  policy_arn = each.value
}

resource "aws_eks_node_group" "base" {
  cluster_name    = aws_eks_cluster.este.name
  node_group_name = "base"
  node_role_arn   = aws_iam_role.nodos.arn
  subnet_ids      = var.subredes_privadas
  instance_types  = ["m7g.large"]
  ami_type        = "AL2023_ARM_64_STANDARD"
  capacity_type   = "ON_DEMAND"

  scaling_config {
    min_size     = 3
    desired_size = 3
    max_size     = 9
  }

  update_config {
    max_unavailable_percentage = 25
  }

  lifecycle {
    ignore_changes = [scaling_config[0].desired_size]
  }

  depends_on = [aws_iam_role_policy_attachment.nodos]
}

# ---------- Add-ons ----------
resource "aws_eks_addon" "complementos" {
  for_each = toset(["vpc-cni", "coredns", "kube-proxy", "eks-pod-identity-agent", "metrics-server"])

  cluster_name = aws_eks_cluster.este.name
  addon_name   = each.value

  depends_on = [aws_eks_node_group.base]
}

# ---------- Pod Identity: rol por ServiceAccount ----------
resource "aws_eks_pod_identity_association" "pedidos" {
  cluster_name    = aws_eks_cluster.este.name
  namespace       = "pedidos"
  service_account = "pedidos"
  role_arn        = var.rol_pedidos_arn

  depends_on = [aws_eks_addon.complementos]
}

output "nombre_cluster" {
  value = aws_eks_cluster.este.name
}

output "endpoint" {
  value = aws_eks_cluster.este.endpoint
}
