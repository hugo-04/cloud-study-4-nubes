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

variable "issuer_jwt" {
  description = "Emisor del token, p. ej. https://auth.modalima.com/"
  type        = string
}

variable "audiencias_jwt" {
  type = list(string)
}

variable "listener_alb_interno_arn" {
  description = "Listener de un ALB INTERNO al que llega el VPC Link."
  type        = string
}

variable "subredes_privadas" {
  type = list(string)
}

variable "sg_vpc_link_id" {
  type = string
}

variable "funcion_lambda_arn" {
  type = string
}

variable "funcion_lambda_nombre" {
  type = string
}

variable "dominio" {
  type = string
}

variable "certificado_acm_arn" {
  description = "Certificado ACM REGIONAL del dominio."
  type        = string
}

locals {
  nombre = "${var.entorno}-tienda"
}

resource "aws_apigatewayv2_api" "http" {
  name          = local.nombre
  protocol_type = "HTTP"

  cors_configuration {
    allow_origins = ["https://tienda.modalima.com"]
    allow_methods = ["GET", "POST", "PUT", "DELETE", "OPTIONS"]
    allow_headers = ["authorization", "content-type"]
    max_age       = 600
  }

  # Con dominio propio y WAF/CloudFront delante, desactiva el endpoint por defecto
  disable_execute_api_endpoint = true
}

# ---------- Autorizador JWT ----------
resource "aws_apigatewayv2_authorizer" "jwt" {
  api_id           = aws_apigatewayv2_api.http.id
  name             = "jwt"
  authorizer_type  = "JWT"
  identity_sources = ["$request.header.Authorization"]

  jwt_configuration {
    issuer   = var.issuer_jwt
    audience = var.audiencias_jwt
  }
}

# ---------- Integración privada: VPC Link -> ALB interno ----------
resource "aws_apigatewayv2_vpc_link" "privado" {
  name               = "${local.nombre}-vpclink"
  subnet_ids         = var.subredes_privadas
  security_group_ids = [var.sg_vpc_link_id]
}

resource "aws_apigatewayv2_integration" "pedidos" {
  api_id             = aws_apigatewayv2_api.http.id
  integration_type   = "HTTP_PROXY"
  integration_method = "ANY"
  integration_uri    = var.listener_alb_interno_arn
  connection_type    = "VPC_LINK"
  connection_id      = aws_apigatewayv2_vpc_link.privado.id
}

resource "aws_apigatewayv2_route" "pedidos" {
  api_id             = aws_apigatewayv2_api.http.id
  route_key          = "ANY /pedidos/{proxy+}"
  target             = "integrations/${aws_apigatewayv2_integration.pedidos.id}"
  authorization_type = "JWT"
  authorizer_id      = aws_apigatewayv2_authorizer.jwt.id

  authorization_scopes = ["pedidos.leer"]
}

# ---------- Integración con Lambda (payload 2.0) ----------
resource "aws_apigatewayv2_integration" "catalogo" {
  api_id                 = aws_apigatewayv2_api.http.id
  integration_type       = "AWS_PROXY"
  integration_uri        = var.funcion_lambda_arn
  payload_format_version = "2.0"
  timeout_milliseconds   = 10000
}

resource "aws_apigatewayv2_route" "catalogo" {
  api_id    = aws_apigatewayv2_api.http.id
  route_key = "GET /catalogo/{id}"
  target    = "integrations/${aws_apigatewayv2_integration.catalogo.id}"
  # Ruta pública de solo lectura: sin autorizador
}

resource "aws_lambda_permission" "apigw" {
  statement_id  = "AllowAPIGatewayInvoke"
  action        = "lambda:InvokeFunction"
  function_name = var.funcion_lambda_nombre
  principal     = "apigateway.amazonaws.com"
  source_arn    = "${aws_apigatewayv2_api.http.execution_arn}/*/*"
}

# ---------- Etapa con logs y límites ----------
resource "aws_cloudwatch_log_group" "acceso" {
  name              = "/apigw/${local.nombre}"
  retention_in_days = 30
}

resource "aws_apigatewayv2_stage" "prod" {
  api_id      = aws_apigatewayv2_api.http.id
  name        = "prod"
  auto_deploy = true

  default_route_settings {
    throttling_burst_limit = 200
    throttling_rate_limit  = 100
  }

  route_settings {
    route_key              = "ANY /pedidos/{proxy+}"
    throttling_burst_limit = 100
    throttling_rate_limit  = 50
  }

  access_log_settings {
    destination_arn = aws_cloudwatch_log_group.acceso.arn
    # Sin cabecera Authorization ni cuerpos
    format = jsonencode({
      requestId      = "$context.requestId"
      ip             = "$context.identity.sourceIp"
      metodo         = "$context.httpMethod"
      ruta           = "$context.routeKey"
      status         = "$context.status"
      latencia       = "$context.responseLatency"
      integracion    = "$context.integrationLatency"
      errorAutorizar = "$context.authorizer.error"
    })
  }
}

# ---------- Dominio propio ----------
resource "aws_apigatewayv2_domain_name" "api" {
  domain_name = var.dominio

  domain_name_configuration {
    certificate_arn = var.certificado_acm_arn
    endpoint_type   = "REGIONAL"
    security_policy = "TLS_1_2"
  }
}

resource "aws_apigatewayv2_api_mapping" "api" {
  api_id      = aws_apigatewayv2_api.http.id
  domain_name = aws_apigatewayv2_domain_name.api.id
  stage       = aws_apigatewayv2_stage.prod.id
}

output "dominio_regional" {
  description = "Crea un alias de Route 53 hacia este nombre."
  value       = aws_apigatewayv2_domain_name.api.domain_name_configuration[0].target_domain_name
}
