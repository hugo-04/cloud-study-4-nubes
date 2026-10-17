# Rol de IAM del AWS Load Balancer Controller con EKS Pod Identity + etiquetas de subred.
# La política de IAM oficial (iam_policy.json de la versión instalada) se crea antes con la CLI
# (ver ../cli/lbc.sh) y aquí solo se referencia su ARN.
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

variable "cluster_name" {
  type = string
}

variable "subredes_publicas" {
  type = list(string)
}

variable "subredes_privadas" {
  type = list(string)
}

variable "politica_lbc_arn" {
  type        = string
  description = "ARN de la política oficial del controlador (creada con la CLI)"
}

# --- Etiquetas para que el controlador descubra las subredes ---
resource "aws_ec2_tag" "elb_publicas" {
  for_each    = toset(var.subredes_publicas)
  resource_id = each.value
  key         = "kubernetes.io/role/elb"
  value       = "1"
}

resource "aws_ec2_tag" "elb_privadas" {
  for_each    = toset(var.subredes_privadas)
  resource_id = each.value
  key         = "kubernetes.io/role/internal-elb"
  value       = "1"
}

# --- Agente de Pod Identity en el clúster ---
resource "aws_eks_addon" "pod_identity_agent" {
  cluster_name = var.cluster_name
  addon_name   = "eks-pod-identity-agent"
}

# --- Rol que asumirá el ServiceAccount del controlador ---
data "aws_iam_policy_document" "confianza_pod_identity" {
  statement {
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "lbc" {
  name               = "${var.entorno}-${var.cluster_name}-lbc"
  assume_role_policy = data.aws_iam_policy_document.confianza_pod_identity.json
}

resource "aws_iam_role_policy_attachment" "lbc" {
  role       = aws_iam_role.lbc.name
  policy_arn = var.politica_lbc_arn
}

resource "aws_eks_pod_identity_association" "lbc" {
  cluster_name    = var.cluster_name
  namespace       = "kube-system"
  service_account = "aws-load-balancer-controller"
  role_arn        = aws_iam_role.lbc.arn

  depends_on = [aws_eks_addon.pod_identity_agent]
}

output "rol_lbc_arn" {
  value = aws_iam_role.lbc.arn
}
