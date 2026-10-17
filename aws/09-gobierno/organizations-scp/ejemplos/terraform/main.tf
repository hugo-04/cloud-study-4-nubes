terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Organizations es un servicio global: región us-east-1, credenciales de la cuenta de administración
provider "aws" {
  region = "us-east-1"
}

variable "regiones_aprobadas" {
  type    = list(string)
  default = ["us-east-1", "sa-east-1"]
}

variable "rol_emergencia" {
  type    = string
  default = "arn:aws:iam::*:role/RolEmergencia"
}

resource "aws_organizations_organization" "org" {
  feature_set = "ALL"

  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "sso.amazonaws.com",
  ]

  enabled_policy_types = ["SERVICE_CONTROL_POLICY"]
}

# --- OU ---
resource "aws_organizations_organizational_unit" "seguridad" {
  name      = "Seguridad"
  parent_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_organizational_unit" "cargas" {
  name      = "Cargas"
  parent_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_organizational_unit" "produccion" {
  name      = "Produccion"
  parent_id = aws_organizations_organizational_unit.cargas.id
}

resource "aws_organizations_organizational_unit" "desarrollo" {
  name      = "Desarrollo"
  parent_id = aws_organizations_organizational_unit.cargas.id
}

resource "aws_organizations_organizational_unit" "ensayo_scp" {
  name      = "EnsayoSCP"
  parent_id = aws_organizations_organization.org.roots[0].id
}

# --- SCP de regiones (se arma aquí para parametrizar las regiones) ---
locals {
  servicios_globales = [
    "account:*", "acm:*", "aws-marketplace:*", "billing:*", "budgets:*", "ce:*", "cloudfront:*",
    "config:*", "cur:*", "directconnect:*", "health:*", "iam:*", "kms:*", "organizations:*",
    "pricing:*", "route53:*", "route53domains:*", "shield:*", "sts:*", "support:*",
    "trustedadvisor:*", "waf:*", "wafv2:*",
  ]
}

resource "aws_organizations_policy" "regiones" {
  name        = "solo-regiones-aprobadas"
  description = "Niega todo fuera de las regiones aprobadas (excepto servicios globales y el rol de emergencia)"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Sid       = "SoloRegionesAprobadas"
      Effect    = "Deny"
      NotAction = local.servicios_globales
      Resource  = "*"
      Condition = {
        StringNotEquals = { "aws:RequestedRegion" = var.regiones_aprobadas }
        ArnNotLike      = { "aws:PrincipalArn" = [var.rol_emergencia] }
      }
    }]
  })
}

resource "aws_organizations_policy" "seguridad" {
  name        = "proteger-seguridad"
  description = "Protege trazas, Config y la pertenencia a la organizacion"
  type        = "SERVICE_CONTROL_POLICY"
  content     = file("${path.module}/../json/scp-proteger-seguridad.json")
}

resource "aws_organizations_policy" "imdsv2" {
  name        = "exigir-imdsv2"
  description = "Instancias EC2 solo con IMDSv2"
  type        = "SERVICE_CONTROL_POLICY"
  content     = file("${path.module}/../json/scp-exigir-imdsv2.json")
}

# --- Adjuntar: primero a la OU de ENSAYO, después a Producción ---
resource "aws_organizations_policy_attachment" "regiones_ensayo" {
  policy_id = aws_organizations_policy.regiones.id
  target_id = aws_organizations_organizational_unit.ensayo_scp.id
}

resource "aws_organizations_policy_attachment" "seguridad_raiz" {
  policy_id = aws_organizations_policy.seguridad.id
  target_id = aws_organizations_organization.org.roots[0].id
}

resource "aws_organizations_policy_attachment" "imdsv2_produccion" {
  policy_id = aws_organizations_policy.imdsv2.id
  target_id = aws_organizations_organizational_unit.produccion.id
}

# --- Una cuenta nueva (la creación es asíncrona y no se elimina con destroy) ---
resource "aws_organizations_account" "tienda_prod" {
  name      = "modalima-tienda-prod"
  email     = "aws+tienda-prod@modalima.example"
  parent_id = aws_organizations_organizational_unit.produccion.id
  role_name = "OrganizationAccountAccessRole"

  lifecycle {
    ignore_changes = [role_name]
  }
}

output "raiz_id" {
  value = aws_organizations_organization.org.roots[0].id
}

output "cuenta_tienda_prod" {
  value = aws_organizations_account.tienda_prod.id
}
