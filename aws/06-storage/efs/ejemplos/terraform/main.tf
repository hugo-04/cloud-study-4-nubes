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

variable "vpc_id" {
  type = string
}

variable "subredes_privadas" {
  type        = map(string)
  description = "Mapa zona => subred privada (un mount target por zona)"
}

variable "sg_aplicacion_id" {
  type        = string
  description = "Grupo de seguridad de las aplicaciones que montan el EFS"
}

resource "aws_kms_key" "efs" {
  description         = "Clave del EFS ${var.entorno}"
  enable_key_rotation = true
}

resource "aws_efs_file_system" "datos" {
  creation_token   = "${var.entorno}-datos"
  encrypted        = true
  kms_key_id       = aws_kms_key.efs.arn
  throughput_mode  = "elastic"
  performance_mode = "generalPurpose"

  lifecycle_policy {
    transition_to_ia = "AFTER_30_DAYS"
  }
  lifecycle_policy {
    transition_to_primary_storage_class = "AFTER_1_ACCESS"
  }

  tags = {
    Name = "${var.entorno}-datos"
  }
}

resource "aws_security_group" "efs" {
  name        = "${var.entorno}-efs"
  description = "NFS desde las aplicaciones"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "nfs" {
  security_group_id            = aws_security_group.efs.id
  referenced_security_group_id = var.sg_aplicacion_id
  from_port                    = 2049
  to_port                      = 2049
  ip_protocol                  = "tcp"
  description                  = "NFS desde la aplicación"
}

resource "aws_efs_mount_target" "zona" {
  for_each        = var.subredes_privadas
  file_system_id  = aws_efs_file_system.datos.id
  subnet_id       = each.value
  security_groups = [aws_security_group.efs.id]
}

# Un punto de acceso por aplicación: raíz y usuario POSIX forzados
resource "aws_efs_access_point" "reportes" {
  file_system_id = aws_efs_file_system.datos.id

  posix_user {
    uid = 1001
    gid = 1001
  }
  root_directory {
    path = "/reportes"
    creation_info {
      owner_uid   = 1001
      owner_gid   = 1001
      permissions = "750"
    }
  }
  tags = {
    Name = "${var.entorno}-reportes"
  }
}

# Solo TLS y solo con montaje autenticado por IAM
data "aws_iam_policy_document" "efs" {
  statement {
    sid       = "SoloTLS"
    effect    = "Deny"
    actions   = ["*"]
    resources = [aws_efs_file_system.datos.arn]
    principals {
      type        = "*"
      identifiers = ["*"]
    }
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
  statement {
    sid       = "PermitirMontajeConIAM"
    effect    = "Allow"
    actions   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
    resources = [aws_efs_file_system.datos.arn]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.actual.account_id}:root"]
    }
  }
}

data "aws_caller_identity" "actual" {}

resource "aws_efs_file_system_policy" "datos" {
  file_system_id = aws_efs_file_system.datos.id
  policy         = data.aws_iam_policy_document.efs.json
}

resource "aws_efs_backup_policy" "datos" {
  file_system_id = aws_efs_file_system.datos.id
  backup_policy {
    status = "ENABLED"
  }
}

# Permisos del rol de la aplicación para montar SOLO mediante el punto de acceso
data "aws_iam_policy_document" "app" {
  statement {
    actions   = ["elasticfilesystem:ClientMount", "elasticfilesystem:ClientWrite"]
    resources = [aws_efs_file_system.datos.arn]
    condition {
      test     = "StringEquals"
      variable = "elasticfilesystem:AccessPointArn"
      values   = [aws_efs_access_point.reportes.arn]
    }
  }
}

resource "aws_iam_policy" "app" {
  name   = "${var.entorno}-efs-reportes"
  policy = data.aws_iam_policy_document.app.json
}

output "efs_id" {
  value = aws_efs_file_system.datos.id
}

output "punto_acceso_reportes" {
  value = aws_efs_access_point.reportes.id
}
