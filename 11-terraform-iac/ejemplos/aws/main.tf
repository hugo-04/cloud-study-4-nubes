# Laboratorio AWS: VPC privada + bucket S3 sin acceso publico, accesible por Gateway Endpoint.
# Material de estudio. Ejecuta: terraform init && terraform plan
# Al terminar: terraform destroy

terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 5.0, < 7.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

variable "region" {
  type    = string
  default = "us-east-1"
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      proyecto = "cloud-study"
      entorno  = "estudio"
    }
  }
}

data "aws_availability_zones" "disponibles" {
  state = "available"
}

resource "random_id" "sufijo" {
  byte_length = 4
}

resource "aws_vpc" "main" {
  cidr_block           = "10.20.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "vpc-estudio"
  }
}

resource "aws_subnet" "app" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.20.1.0/24"
  availability_zone = data.aws_availability_zones.disponibles.names[0]

  tags = {
    Name = "snet-app"
  }
}

# Tabla de rutas privada: sin Internet Gateway, asi que la subnet no tiene salida publica.
resource "aws_route_table" "privada" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "rt-privada"
  }
}

resource "aws_route_table_association" "app" {
  subnet_id      = aws_subnet.app.id
  route_table_id = aws_route_table.privada.id
}

resource "aws_security_group" "app" {
  name        = "app-sg-estudio"
  description = "Aplicacion: HTTPS solo desde la subnet web"
  vpc_id      = aws_vpc.main.id

  ingress {
    description = "HTTPS desde la subnet web"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["10.20.0.0/24"]
  }

  egress {
    description = "Salida solo dentro de la VPC"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.20.0.0/16"]
  }

  tags = {
    Name = "sg-app"
  }
}

# Gateway Endpoint de S3: el trafico a S3 no sale a internet.
resource "aws_vpc_endpoint" "s3" {
  vpc_id            = aws_vpc.main.id
  service_name      = "com.amazonaws.${var.region}.s3"
  vpc_endpoint_type = "Gateway"
  route_table_ids   = [aws_route_table.privada.id]

  tags = {
    Name = "vpce-s3"
  }
}

resource "aws_s3_bucket" "datos" {
  bucket = "modalima-estudio-${random_id.sufijo.hex}"
}

resource "aws_s3_bucket_public_access_block" "datos" {
  bucket                  = aws_s3_bucket.datos.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "datos" {
  bucket = aws_s3_bucket.datos.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "datos" {
  bucket = aws_s3_bucket.datos.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# Politica: negar cualquier acceso que no use TLS.
data "aws_iam_policy_document" "solo_tls" {
  statement {
    sid       = "DenegarSinTLS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.datos.arn, "${aws_s3_bucket.datos.arn}/*"]

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
}

resource "aws_s3_bucket_policy" "datos" {
  bucket = aws_s3_bucket.datos.id
  policy = data.aws_iam_policy_document.solo_tls.json
}

output "nombre_bucket" {
  value = aws_s3_bucket.datos.bucket
}

output "subnet_app_id" {
  value = aws_subnet.app.id
}
