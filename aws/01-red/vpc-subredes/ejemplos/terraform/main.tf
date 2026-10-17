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

  default_tags {
    tags = {
      app   = "tienda"
      env   = var.entorno
      owner = "equipo-plataforma"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "entorno" {
  type = string
  validation {
    condition     = contains(["dev", "prod"], var.entorno)
    error_message = "entorno debe ser dev o prod."
  }
}

variable "cidr_vpc" {
  description = "Bloque asignado por el registro central de direcciones."
  type        = string
  default     = "10.20.0.0/16"
  validation {
    condition     = can(cidrnetmask(var.cidr_vpc)) && tonumber(split("/", var.cidr_vpc)[1]) <= 18
    error_message = "cidr_vpc debe ser un CIDR válido de /18 o mayor."
  }
}

variable "cantidad_az" {
  type    = number
  default = 3
  validation {
    condition     = var.cantidad_az >= 2 && var.cantidad_az <= 3
    error_message = "Usa 2 o 3 zonas de disponibilidad."
  }
}

variable "nat_por_az" {
  description = "true en producción (un NAT por AZ); false en dev para ahorrar (un solo NAT)."
  type        = bool
  default     = true
}

variable "bucket_flow_logs_arn" {
  description = "ARN del bucket (cuenta de registros) para los Flow Logs. Vacío = sin Flow Logs."
  type        = string
  default     = ""
}

data "aws_availability_zones" "disponibles" {
  state = "available"
}

locals {
  azs = slice(data.aws_availability_zones.disponibles.names, 0, var.cantidad_az)

  publicas = { for i, az in local.azs : az => cidrsubnet(var.cidr_vpc, 8, i) }       # /24
  apps     = { for i, az in local.azs : az => cidrsubnet(var.cidr_vpc, 6, 4 + i) }   # /22
  datos    = { for i, az in local.azs : az => cidrsubnet(var.cidr_vpc, 8, 100 + i) } # /24

  azs_con_nat = var.nat_por_az ? local.azs : [local.azs[0]]
}

resource "aws_vpc" "principal" {
  cidr_block           = var.cidr_vpc
  enable_dns_support   = true
  enable_dns_hostnames = true # necesario para los endpoints de interfaz con DNS privado

  tags = { Name = "vpc-tienda-${var.entorno}" }
}

resource "aws_internet_gateway" "principal" {
  vpc_id = aws_vpc.principal.id
  tags   = { Name = "igw-tienda-${var.entorno}" }
}

resource "aws_subnet" "publica" {
  for_each = local.publicas

  vpc_id                  = aws_vpc.principal.id
  availability_zone       = each.key
  cidr_block              = each.value
  map_public_ip_on_launch = false # las IP públicas se piden a propósito, no por defecto

  tags = { Name = "snet-publica-${each.key}", nivel = "publica" }
}

resource "aws_subnet" "app" {
  for_each = local.apps

  vpc_id            = aws_vpc.principal.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = { Name = "snet-app-${each.key}", nivel = "app" }
}

resource "aws_subnet" "datos" {
  for_each = local.datos

  vpc_id            = aws_vpc.principal.id
  availability_zone = each.key
  cidr_block        = each.value

  tags = { Name = "snet-datos-${each.key}", nivel = "datos" }
}

# Salida a internet de las privadas: un NAT por AZ (producción) o uno solo (dev)
resource "aws_eip" "nat" {
  for_each = toset(local.azs_con_nat)
  domain   = "vpc"
  tags     = { Name = "eip-nat-${each.key}" }
}

resource "aws_nat_gateway" "por_az" {
  for_each = toset(local.azs_con_nat)

  allocation_id = aws_eip.nat[each.key].id
  subnet_id     = aws_subnet.publica[each.key].id
  tags          = { Name = "nat-${each.key}" }

  depends_on = [aws_internet_gateway.principal]
}

# Rutas
resource "aws_route_table" "publica" {
  vpc_id = aws_vpc.principal.id
  tags   = { Name = "rt-publica" }
}

resource "aws_route" "publica_internet" {
  route_table_id         = aws_route_table.publica.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.principal.id
}

resource "aws_route_table_association" "publica" {
  for_each       = aws_subnet.publica
  subnet_id      = each.value.id
  route_table_id = aws_route_table.publica.id
}

resource "aws_route_table" "app" {
  for_each = toset(local.azs)
  vpc_id   = aws_vpc.principal.id
  tags     = { Name = "rt-app-${each.key}" }
}

resource "aws_route" "app_salida" {
  for_each = toset(local.azs)

  route_table_id         = aws_route_table.app[each.key].id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.por_az[var.nat_por_az ? each.key : local.azs[0]].id
}

resource "aws_route_table_association" "app" {
  for_each       = aws_subnet.app
  subnet_id      = each.value.id
  route_table_id = aws_route_table.app[each.key].id
}

# Datos: tabla SIN ruta a internet
resource "aws_route_table" "datos" {
  vpc_id = aws_vpc.principal.id
  tags   = { Name = "rt-datos" }
}

resource "aws_route_table_association" "datos" {
  for_each       = aws_subnet.datos
  subnet_id      = each.value.id
  route_table_id = aws_route_table.datos.id
}

# Registros de flujo (opcional) hacia el bucket de la cuenta de registros
resource "aws_flow_log" "vpc" {
  count = var.bucket_flow_logs_arn == "" ? 0 : 1

  vpc_id               = aws_vpc.principal.id
  traffic_type         = "ALL"
  log_destination_type = "s3"
  log_destination      = var.bucket_flow_logs_arn
}

output "vpc_id" {
  value = aws_vpc.principal.id
}

output "subredes_app" {
  value = { for az, s in aws_subnet.app : az => s.id }
}

output "subredes_datos" {
  value = { for az, s in aws_subnet.datos : az => s.id }
}
