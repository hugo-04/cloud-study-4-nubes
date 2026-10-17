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

variable "clave_kms_arn" {
  description = "CMK para los SecureString."
  type        = string
}

locals {
  base = "/${var.entorno}/pedidos"

  # Configuración NO sensible: va en el código (y en Git)
  config = {
    "db/url"            = "jdbc:postgresql://pedidos.cluster-xxxx.us-east-1.rds.amazonaws.com:5432/pedidos"
    "db/pool-max"       = "20"
    "features/nueva-ui" = "false"
    "http/timeout-ms"   = "3000"
  }
}

resource "aws_ssm_parameter" "config" {
  for_each = local.config

  name  = "${local.base}/${each.key}"
  type  = "String"
  value = each.value
  tier  = "Standard"

  tags = { servicio = "pedidos", entorno = var.entorno }
}

resource "aws_ssm_parameter" "colas" {
  name  = "${local.base}/colas/lista"
  type  = "StringList"
  value = "pedidos-pagados,pedidos-enviados"
  tags  = { servicio = "pedidos", entorno = var.entorno }
}

# SecureString: el contenedor se crea con un valor MARCADOR y el valor real se carga fuera de banda
# (así el secreto real nunca queda en el estado ni en Git).
resource "aws_ssm_parameter" "api_clave" {
  name   = "${local.base}/pagos/api-clave"
  type   = "SecureString"
  key_id = var.clave_kms_arn
  value  = "CAMBIAR-FUERA-DE-BANDA"
  tags   = { servicio = "pedidos", entorno = var.entorno }

  lifecycle {
    ignore_changes = [value]
  }
}

# Política de lectura por ruta para el rol de la aplicación
data "aws_iam_policy_document" "lectura" {
  statement {
    actions = ["ssm:GetParametersByPath", "ssm:GetParameter", "ssm:GetParameters"]
    resources = [
      "arn:aws:ssm:${var.region}:*:parameter${local.base}",
      "arn:aws:ssm:${var.region}:*:parameter${local.base}/*",
    ]
  }

  statement {
    actions   = ["kms:Decrypt"]
    resources = [var.clave_kms_arn]

    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${var.region}.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "lectura" {
  name   = "${var.entorno}-pedidos-lee-parametros"
  policy = data.aws_iam_policy_document.lectura.json
}

# Lectura de un parámetro público de AWS (ejemplo: última AMI de Amazon Linux)
data "aws_ssm_parameter" "ami" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

output "politica_lectura_arn" {
  value = aws_iam_policy.lectura.arn
}

output "ami_recomendada" {
  value     = data.aws_ssm_parameter.ami.value
  sensitive = false
}
