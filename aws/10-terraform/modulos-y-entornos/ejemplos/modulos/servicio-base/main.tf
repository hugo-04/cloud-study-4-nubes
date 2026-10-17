locals {
  prefijo = "${var.entorno}-${var.nombre}"

  etiquetas = merge(var.etiquetas_extra, {
    servicio       = var.nombre
    entorno        = var.entorno
    dueno          = var.dueno
    equipo         = var.equipo
    gestionado_por = "terraform"
  })
}

# ---------------------------------------------------------------- Colas (el cifrado NO es una variable: es parte del contrato)
resource "aws_sqs_queue" "dlq" {
  name                      = "${local.prefijo}-dlq"
  message_retention_seconds = 14 * 24 * 60 * 60
  sqs_managed_sse_enabled   = true
  tags                      = local.etiquetas
}

resource "aws_sqs_queue" "principal" {
  name                       = local.prefijo
  visibility_timeout_seconds = 60
  message_retention_seconds  = var.retencion_mensajes_dias * 24 * 60 * 60
  sqs_managed_sse_enabled    = true
  tags                       = local.etiquetas

  redrive_policy = jsonencode({
    deadLetterTargetArn = aws_sqs_queue.dlq.arn
    maxReceiveCount     = var.max_receives
  })
}

resource "aws_sqs_queue_redrive_allow_policy" "dlq" {
  queue_url = aws_sqs_queue.dlq.id

  redrive_allow_policy = jsonencode({
    redrivePermission = "byQueue"
    sourceQueueArns   = [aws_sqs_queue.principal.arn]
  })
}

# ---------------------------------------------------------------- Logs
resource "aws_cloudwatch_log_group" "app" {
  name              = "/app/${local.prefijo}"
  retention_in_days = var.retencion_logs_dias
  tags              = local.etiquetas
}

# ---------------------------------------------------------------- Rol de la tarea (nombre app-*, con límite de permisos)
resource "aws_iam_role" "tarea" {
  name                 = "app-${local.prefijo}"
  permissions_boundary = var.arn_limite_permisos
  tags                 = local.etiquetas

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ecs-tasks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  lifecycle {
    precondition {
      condition     = var.entorno != "prod" || var.arn_limite_permisos != null
      error_message = "En prod el rol debe crearse con un límite de permisos (arn_limite_permisos)."
    }
  }
}

resource "aws_iam_role_policy" "minimos" {
  name = "minimos"
  role = aws_iam_role.tarea.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "SoloMiCola"
        Effect = "Allow"
        Action = [
          "sqs:ReceiveMessage",
          "sqs:DeleteMessage",
          "sqs:ChangeMessageVisibility",
          "sqs:GetQueueAttributes",
          "sqs:SendMessage",
        ]
        Resource = aws_sqs_queue.principal.arn
      },
      {
        Sid      = "SoloMisLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = "${aws_cloudwatch_log_group.app.arn}:*"
      },
    ]
  })
}
