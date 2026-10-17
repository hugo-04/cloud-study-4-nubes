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

variable "vpc_id" {
  type = string
}

variable "tablas_ruta_app_ids" {
  description = "Tablas de rutas de las subredes de aplicación (para los endpoints de puerta de enlace)."
  type        = list(string)
}

variable "subredes_endpoints_ids" {
  description = "Una subred por AZ para las ENI de los endpoints de interfaz."
  type        = list(string)
}

variable "sg_app_id" {
  type = string
}

variable "servicios_interfaz" {
  description = "Servicios de AWS que se usarán por PrivateLink."
  type        = set(string)
  default     = ["ecr.api", "ecr.dkr", "logs", "sts", "secretsmanager", "sqs", "kms"]
}

variable "bucket_datos" {
  description = "Bucket al que se limita el endpoint de S3."
  type        = string
}

# ---------- Endpoints de puerta de enlace (gratis) ----------
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.tablas_ruta_app_ids

  # Las capas de ECR viven en buckets de S3 de AWS: no restrinjas a solo tu bucket si usas ECR sin NAT
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "TuBucket"
        Effect    = "Allow"
        Principal = "*"
        Action    = ["s3:GetObject", "s3:PutObject", "s3:ListBucket"]
        Resource  = ["arn:aws:s3:::${var.bucket_datos}", "arn:aws:s3:::${var.bucket_datos}/*"]
      },
      {
        Sid       = "CapasDeEcr"
        Effect    = "Allow"
        Principal = "*"
        Action    = "s3:GetObject"
        Resource  = "arn:aws:s3:::prod-${var.region}-starport-layer-bucket/*"
      }
    ]
  })

  tags = { Name = "vpce-s3" }
}

resource "aws_vpc_endpoint" "dynamodb" {
  vpc_id            = var.vpc_id
  service_name      = "com.amazonaws.${var.region}.dynamodb"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = var.tablas_ruta_app_ids
  tags              = { Name = "vpce-dynamodb" }
}

# ---------- SG de los endpoints de interfaz ----------
resource "aws_security_group" "endpoints" {
  name_prefix = "tienda-endpoints-"
  description = "ENI de endpoints de interfaz"
  vpc_id      = var.vpc_id
  tags        = { Name = "sg-endpoints", rol = "endpoints" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "endpoints_desde_app" {
  security_group_id            = aws_security_group.endpoints.id
  description                  = "HTTPS desde la aplicacion"
  ip_protocol                  = "tcp"
  from_port                    = 443
  to_port                      = 443
  referenced_security_group_id = var.sg_app_id
}

# ---------- Endpoints de interfaz con DNS privado ----------
resource "aws_vpc_endpoint" "interfaz" {
  for_each = var.servicios_interfaz

  vpc_id              = var.vpc_id
  service_name        = "com.amazonaws.${var.region}.${each.value}"
  vpc_endpoint_type   = "Interface"
  subnet_ids          = var.subredes_endpoints_ids
  security_group_ids  = [aws_security_group.endpoints.id]
  private_dns_enabled = true # el nombre normal resuelve a la IP privada

  tags = { Name = "vpce-${each.value}" }
}

# ---------- Zona privada para nombres internos ----------
resource "aws_route53_zone" "interna" {
  name = "modalima.internal"

  vpc {
    vpc_id = var.vpc_id
  }

  comment = "Nombres internos de la tienda"
}

resource "aws_route53_record" "pedidos" {
  zone_id = aws_route53_zone.interna.zone_id
  name    = "pedidos.modalima.internal"
  type    = "CNAME"
  ttl     = 60
  records = ["alb-interno-123456.us-east-1.elb.amazonaws.com"]
}

# ---------- Publicar un servicio propio con PrivateLink ----------
variable "nlb_arn" {
  description = "ARN del Network Load Balancer interno que expone el servicio (vacío = no publicar)."
  type        = string
  default     = ""
}

variable "cuentas_consumidoras" {
  type    = list(string)
  default = []
}

resource "aws_vpc_endpoint_service" "pagos" {
  count = var.nlb_arn == "" ? 0 : 1

  acceptance_required        = true # aprobación manual de cada consumidor
  network_load_balancer_arns = [var.nlb_arn]
  allowed_principals         = [for c in var.cuentas_consumidoras : "arn:aws:iam::${c}:root"]
  tags                       = { Name = "svc-pagos" }
}

output "dns_endpoints_interfaz" {
  value = { for k, v in aws_vpc_endpoint.interfaz : k => v.dns_entry[0].dns_name }
}
