terraform {
  required_version = ">= 1.5"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }
}

# Región principal de tus recursos
provider "aws" {
  region = var.region
}

# WAF con alcance CLOUDFRONT y los certificados de CloudFront viven en us-east-1
provider "aws" {
  alias  = "us_east_1"
  region = "us-east-1"
}

variable "region" {
  type    = string
  default = "us-east-1"
}

variable "entorno" {
  type = string
}

variable "dominio_sitio" {
  description = "Dominio público, p. ej. www.modalima.com"
  type        = string
}

variable "certificado_acm_us_east_1_arn" {
  description = "Certificado de ACM emitido en us-east-1 para el dominio."
  type        = string
}

variable "dns_alb_origen" {
  description = "Nombre DNS del ALB que sirve la API (el origen dinámico)."
  type        = string
}

variable "secreto_origen" {
  description = "Valor de la cabecera X-Origin-Verify (guárdalo en Secrets Manager; rota con dos valores)."
  type        = string
  sensitive   = true
}

locals {
  nombre = "${var.entorno}-sitio"
}

# ---------- Bucket privado para los estáticos ----------
resource "aws_s3_bucket" "sitio" {
  bucket = "modalima-${local.nombre}"
}

resource "aws_s3_bucket_public_access_block" "sitio" {
  bucket                  = aws_s3_bucket.sitio.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_cloudfront_origin_access_control" "sitio" {
  name                              = "${local.nombre}-oac"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

# ---------- Políticas administradas (por nombre, sin IDs a mano) ----------
data "aws_cloudfront_cache_policy" "optimizada" {
  name = "Managed-CachingOptimized"
}

data "aws_cloudfront_cache_policy" "sin_cache" {
  name = "Managed-CachingDisabled"
}

data "aws_cloudfront_origin_request_policy" "todo_menos_host" {
  name = "Managed-AllViewerExceptHostHeader"
}

data "aws_cloudfront_response_headers_policy" "seguridad" {
  name = "Managed-SecurityHeadersPolicy"
}

# ---------- WAF (alcance CLOUDFRONT, en us-east-1) ----------
resource "aws_wafv2_web_acl" "sitio" {
  provider    = aws.us_east_1
  name        = "${local.nombre}-waf"
  description = "Reglas gestionadas + limite por tasa"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  rule {
    name     = "reglas-comunes"
    priority = 10

    override_action {
      count {} # EMPIEZA EN COUNT; pasa a none {} (bloquear) tras revisar falsos positivos
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "reglas-comunes"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "entradas-maliciosas"
    priority = 20

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesKnownBadInputsRuleSet"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "entradas-maliciosas"
      sampled_requests_enabled   = true
    }
  }

  rule {
    name     = "reputacion-ip"
    priority = 30

    override_action {
      count {}
    }

    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesAmazonIpReputationList"
        vendor_name = "AWS"
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "reputacion-ip"
      sampled_requests_enabled   = true
    }
  }

  # Límite por IP en /login: 100 peticiones por ventana de 5 minutos
  rule {
    name     = "tasa-login"
    priority = 5

    action {
      count {} # también en Count al inicio
    }

    statement {
      rate_based_statement {
        limit              = 100
        aggregate_key_type = "IP"

        scope_down_statement {
          byte_match_statement {
            search_string         = "/api/login"
            positional_constraint = "STARTS_WITH"

            field_to_match {
              uri_path {}
            }

            text_transformation {
              priority = 0
              type     = "LOWERCASE"
            }
          }
        }
      }
    }

    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "tasa-login"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "${local.nombre}-waf"
    sampled_requests_enabled   = true
  }
}

# ---------- Distribución ----------
resource "aws_cloudfront_distribution" "sitio" {
  enabled             = true
  is_ipv6_enabled     = true
  http_version        = "http2and3"
  default_root_object = "index.html"
  price_class         = "PriceClass_100"
  aliases             = [var.dominio_sitio]
  web_acl_id          = aws_wafv2_web_acl.sitio.arn

  # Origen 1: S3 privado con OAC
  origin {
    origin_id                = "s3-sitio"
    domain_name              = aws_s3_bucket.sitio.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.sitio.id
  }

  # Origen 2: la API (ALB) con cabecera secreta
  origin {
    origin_id   = "alb-api"
    domain_name = var.dns_alb_origen

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 30
    }

    custom_header {
      name  = "X-Origin-Verify"
      value = var.secreto_origen
    }
  }

  # Por defecto: estáticos con caché agresiva
  default_cache_behavior {
    target_origin_id           = "s3-sitio"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = data.aws_cloudfront_cache_policy.optimizada.id
    response_headers_policy_id = data.aws_cloudfront_response_headers_policy.seguridad.id
  }

  # /api/*: sin caché; todo se reenvía al origen salvo el Host
  ordered_cache_behavior {
    path_pattern             = "/api/*"
    target_origin_id         = "alb-api"
    viewer_protocol_policy   = "https-only"
    allowed_methods          = ["GET", "HEAD", "OPTIONS", "PUT", "POST", "PATCH", "DELETE"]
    cached_methods           = ["GET", "HEAD"]
    compress                 = true
    cache_policy_id          = data.aws_cloudfront_cache_policy.sin_cache.id
    origin_request_policy_id = data.aws_cloudfront_origin_request_policy.todo_menos_host.id
  }

  # SPA: rutas profundas devuelven index.html
  custom_error_response {
    error_code            = 403
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  custom_error_response {
    error_code            = 404
    response_code         = 200
    response_page_path    = "/index.html"
    error_caching_min_ttl = 10
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = var.certificado_acm_us_east_1_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

# ---------- Política del bucket: solo esta distribución lee ----------
data "aws_iam_policy_document" "bucket" {
  statement {
    sid       = "SoloCloudFrontLee"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.sitio.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.sitio.arn]
    }
  }

  statement {
    sid       = "SoloTLS"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.sitio.arn, "${aws_s3_bucket.sitio.arn}/*"]

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

resource "aws_s3_bucket_policy" "sitio" {
  bucket = aws_s3_bucket.sitio.id
  policy = data.aws_iam_policy_document.bucket.json
}

output "dominio_cloudfront" {
  description = "Crea un alias (A/AAAA) de Route 53 hacia este nombre."
  value       = aws_cloudfront_distribution.sitio.domain_name
}
