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

variable "cidr_subredes_app" {
  description = "CIDR de las subredes de aplicación (para la NACL de datos)."
  type        = list(string)
}

variable "subredes_datos_ids" {
  type = list(string)
}

variable "cidrs_proveedor_pagos" {
  description = "Rangos de salida del proveedor de pagos (lista de prefijos compartida)."
  type        = list(string)
  default     = ["203.0.113.0/24", "198.51.100.0/24"]
}

# ---------- Lista de prefijos reutilizable ----------
resource "aws_ec2_managed_prefix_list" "pagos" {
  name           = "proveedor-pagos"
  address_family = "IPv4"
  max_entries    = 20

  dynamic "entry" {
    for_each = toset(var.cidrs_proveedor_pagos)
    content {
      cidr        = entry.value
      description = "Rango publicado por el proveedor"
    }
  }
}

# ---------- Un grupo de seguridad por rol ----------
resource "aws_security_group" "alb" {
  name_prefix = "tienda-alb-"
  description = "Balanceador publico"
  vpc_id      = var.vpc_id
  tags        = { Name = "sg-alb", rol = "alb" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "app" {
  name_prefix = "tienda-app-"
  description = "Contenedores de la aplicacion"
  vpc_id      = var.vpc_id
  tags        = { Name = "sg-app", rol = "app" }

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_security_group" "datos" {
  name_prefix = "tienda-datos-"
  description = "Bases de datos y caches"
  vpc_id      = var.vpc_id
  tags        = { Name = "sg-datos", rol = "datos" }

  lifecycle {
    create_before_destroy = true
  }
}

# Entrada
resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  description       = "HTTPS desde internet"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "0.0.0.0/0"
}

resource "aws_vpc_security_group_ingress_rule" "app_desde_alb" {
  security_group_id            = aws_security_group.app.id
  description                  = "8080 solo desde el balanceador"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.alb.id
}

resource "aws_vpc_security_group_ingress_rule" "datos_desde_app" {
  security_group_id            = aws_security_group.datos.id
  description                  = "PostgreSQL solo desde la aplicacion"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.app.id
}

# Salida restringida en producción
resource "aws_vpc_security_group_egress_rule" "alb_a_app" {
  security_group_id            = aws_security_group.alb.id
  description                  = "Hacia la aplicacion"
  ip_protocol                  = "tcp"
  from_port                    = 8080
  to_port                      = 8080
  referenced_security_group_id = aws_security_group.app.id
}

resource "aws_vpc_security_group_egress_rule" "app_a_datos" {
  security_group_id            = aws_security_group.app.id
  description                  = "Hacia la base"
  ip_protocol                  = "tcp"
  from_port                    = 5432
  to_port                      = 5432
  referenced_security_group_id = aws_security_group.datos.id
}

resource "aws_vpc_security_group_egress_rule" "app_a_pagos" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS al proveedor de pagos"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  prefix_list_id    = aws_ec2_managed_prefix_list.pagos.id
}

resource "aws_vpc_security_group_egress_rule" "app_https_endpoints" {
  security_group_id = aws_security_group.app.id
  description       = "HTTPS hacia endpoints de la VPC y servicios"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = "10.20.0.0/16"
}

# ---------- NACL de datos: capa extra, con retorno ----------
resource "aws_network_acl" "datos" {
  vpc_id     = var.vpc_id
  subnet_ids = var.subredes_datos_ids
  tags       = { Name = "nacl-datos" }
}

resource "aws_network_acl_rule" "datos_entrada_pg" {
  count = length(var.cidr_subredes_app)

  network_acl_id = aws_network_acl.datos.id
  rule_number    = 100 + count.index
  egress         = false
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.cidr_subredes_app[count.index]
  from_port      = 5432
  to_port        = 5432
}

resource "aws_network_acl_rule" "datos_salida_efimeros" {
  count = length(var.cidr_subredes_app)

  network_acl_id = aws_network_acl.datos.id
  rule_number    = 100 + count.index
  egress         = true
  protocol       = "tcp"
  rule_action    = "allow"
  cidr_block     = var.cidr_subredes_app[count.index]
  from_port      = 1024
  to_port        = 65535
}

output "sg_ids" {
  value = {
    alb   = aws_security_group.alb.id
    app   = aws_security_group.app.id
    datos = aws_security_group.datos.id
  }
}
