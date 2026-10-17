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

variable "bucket_artefactos" {
  type = string
}

variable "clave_jar" {
  description = "Ruta del JAR en el bucket de artefactos."
  type        = string
}

variable "clave_kms_arn" {
  type = string
}

variable "memoria_mb" {
  type    = number
  default = 1024
}

variable "timeout_s" {
  type    = number
  default = 30
}

variable "subredes_privadas" {
  description = "Vacío = fuera de la VPC."
  type        = list(string)
  default     = []
}

variable "grupos_seguridad" {
  type    = list(string)
  default = []
}

locals {
  nombre = "${var.entorno}-pedidos-procesar"
}

# ---------- Cola de entrada + DLQ ----------
resource "aws_sqs_queue" "dlq" {
  name                      = "${var.entorno}-pedidos-pagados-dlq"
  message_retention_seconds = 1209600
  kms_master_key_id         = var.clave_kms_arn
}

resource "aws_sqs_queue" "entrada" {
  name = "${var.entorno}-pedidos-pagados"

  # Regla: visibilidad >= 6 x timeout de la función
  visibility_timeout_seconds = var.timeout_s * 6
  kms_master_key_id          = var.clave_kms_arn

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = 5
  })
}

# ---------- Rol de ejecución ----------
data "aws_iam_policy_document" "confianza" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "funcion" {
  name               = "${local.nombre}-ejecucion"
  assume_role_policy = data.aws_iam_policy_document.confianza.json
}

resource "aws_iam_role_policy_attachment" "logs" {
  role       = aws_iam_role.funcion.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

resource "aws_iam_role_policy_attachment" "vpc" {
  count      = length(var.subredes_privadas) > 0 ? 1 : 0
  role       = aws_iam_role.funcion.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaVPCAccessExecutionRole"
}

data "aws_iam_policy_document" "permisos" {
  statement {
    sid       = "LeerLaCola"
    actions   = ["sqs:ReceiveMessage", "sqs:DeleteMessage", "sqs:GetQueueAttributes"]
    resources = [aws_sqs_queue.entrada.arn]
  }

  statement {
    sid       = "DescifrarMensajes"
    actions   = ["kms:Decrypt"]
    resources = [var.clave_kms_arn]
  }
}

resource "aws_iam_role_policy" "permisos" {
  name   = "permisos-de-la-funcion"
  role   = aws_iam_role.funcion.id
  policy = data.aws_iam_policy_document.permisos.json
}

# ---------- Logs ----------
resource "aws_cloudwatch_log_group" "funcion" {
  name              = "/aws/lambda/${local.nombre}"
  retention_in_days = 30
}

# ---------- Función ----------
resource "aws_lambda_function" "procesar" {
  function_name = local.nombre
  role          = aws_iam_role.funcion.arn
  runtime       = "java21"
  handler       = "com.modalima.pedidos.PedidosHandler::handleRequest"
  architectures = ["arm64"]
  memory_size   = var.memoria_mb
  timeout       = var.timeout_s
  s3_bucket     = var.bucket_artefactos
  s3_key        = var.clave_jar
  publish       = true # SnapStart necesita versiones publicadas
  kms_key_arn   = var.clave_kms_arn

  snap_start {
    apply_on = "PublishedVersions"
  }

  environment {
    variables = {
      CONFIG_RUTA       = "/${var.entorno}/pedidos"
      JAVA_TOOL_OPTIONS = "-XX:+TieredCompilation -XX:TieredStopAtLevel=1"
    }
  }

  dynamic "vpc_config" {
    for_each = length(var.subredes_privadas) > 0 ? [1] : []

    content {
      subnet_ids         = var.subredes_privadas
      security_group_ids = var.grupos_seguridad
    }
  }

  depends_on = [aws_cloudwatch_log_group.funcion, aws_iam_role_policy_attachment.logs]
}

resource "aws_lambda_alias" "prod" {
  name             = "prod"
  function_name    = aws_lambda_function.procesar.function_name
  function_version = aws_lambda_function.procesar.version
}

# ---------- SQS -> Lambda con fallos parciales ----------
resource "aws_lambda_event_source_mapping" "cola" {
  event_source_arn                   = aws_sqs_queue.entrada.arn
  function_name                      = aws_lambda_alias.prod.arn
  batch_size                         = 10
  maximum_batching_window_in_seconds = 5
  function_response_types            = ["ReportBatchItemFailures"]

  scaling_config {
    maximum_concurrency = 20 # techo para no agotar la concurrencia de la cuenta
  }
}

output "funcion" {
  value = aws_lambda_function.procesar.function_name
}

output "cola_entrada_url" {
  value = aws_sqs_queue.entrada.url
}
