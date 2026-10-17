terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
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

variable "cluster" {
  type = string
}

variable "cola_pedidos_arn" {
  type = string
}

variable "bucket_facturas" {
  type = string
}

data "aws_eks_cluster" "c" {
  name = var.cluster
}

# ============ Opción A: EKS Pod Identity (recomendada en EC2) ============
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = var.cluster
  addon_name   = "eks-pod-identity-agent"
}

data "aws_iam_policy_document" "confianza_pod_identity" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]

    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "permisos_pedidos" {
  statement {
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [var.cola_pedidos_arn]
  }
}

resource "aws_iam_role" "pedidos" {
  name               = "${var.cluster}-pedidos"
  assume_role_policy = data.aws_iam_policy_document.confianza_pod_identity.json
}

resource "aws_iam_role_policy" "pedidos" {
  name   = "permisos"
  role   = aws_iam_role.pedidos.id
  policy = data.aws_iam_policy_document.permisos_pedidos.json
}

resource "aws_eks_pod_identity_association" "pedidos" {
  cluster_name    = var.cluster
  namespace       = "tienda"
  service_account = "pedidos"
  role_arn        = aws_iam_role.pedidos.arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}

# ============ Opción B: IRSA (necesario en Fargate) ============
data "tls_certificate" "oidc" {
  url = data.aws_eks_cluster.c.identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "eks" {
  url             = data.aws_eks_cluster.c.identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.oidc.certificates[0].sha1_fingerprint]
}

locals {
  emisor = replace(aws_iam_openid_connect_provider.eks.url, "https://", "")
}

data "aws_iam_policy_document" "confianza_irsa" {
  statement {
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.eks.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.emisor}:sub"
      values   = ["system:serviceaccount:facturas:facturador"] # el pod exacto
    }

    condition {
      test     = "StringEquals"
      variable = "${local.emisor}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "permisos_facturador" {
  statement {
    actions   = ["s3:PutObject"]
    resources = ["arn:aws:s3:::${var.bucket_facturas}/facturas/*"]
  }
}

resource "aws_iam_role" "facturador" {
  name               = "${var.cluster}-facturador-irsa"
  assume_role_policy = data.aws_iam_policy_document.confianza_irsa.json
}

resource "aws_iam_role_policy" "facturador" {
  name   = "permisos"
  role   = aws_iam_role.facturador.id
  policy = data.aws_iam_policy_document.permisos_facturador.json
}

output "anotacion_irsa" {
  description = "Valor de eks.amazonaws.com/role-arn para el ServiceAccount facturas/facturador"
  value       = aws_iam_role.facturador.arn
}
