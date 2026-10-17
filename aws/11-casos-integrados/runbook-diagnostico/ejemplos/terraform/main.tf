# Alertas por SÍNTOMA, panel de las 4 señales, consultas guardadas y avisos de AWS Health.
# Se aplica por entorno; los recursos observados (ALB, colas, NAT) entran como variables.
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

variable "alb_arn_suffix" {
  type        = string
  description = "Sufijo del ALB (ej. app/prod-tienda/50dc6c495c0c9188), el valor de la dimensión LoadBalancer"
}

variable "cola_facturacion" {
  type        = string
  description = "Nombre de la cola de facturación"
}

variable "dlq_facturacion" {
  type        = string
  description = "Nombre de su cola de mensajes fallidos"
}

variable "nat_gateway_id" {
  type        = string
  description = "ID de la NAT gateway de la que dependen las salidas a Internet"
}

variable "grupo_logs_app" {
  type        = string
  description = "Grupo de logs de la aplicación (donde la sonda escribe sus líneas)"
}

variable "correos_guardia" {
  type        = list(string)
  description = "Correos que reciben la página (la guardia). Para chat o buscapersonas se usa un destino HTTPS aparte."
}

variable "umbral_errores_pct" {
  type    = number
  default = 2
  validation {
    condition     = var.umbral_errores_pct > 0 && var.umbral_errores_pct <= 50
    error_message = "El umbral de errores debe estar entre 0 y 50 %."
  }
}

variable "latencia_p95_segundos" {
  type    = number
  default = 1.5
}

variable "url_runbook" {
  type    = string
  default = "https://wiki.modalima.example/runbooks/tienda"
}

data "aws_caller_identity" "actual" {}

locals {
  prefijo = "${var.entorno}-tienda"
  etiquetas = {
    entorno = var.entorno
    sistema = "tienda"
  }
  # La descripción de cada alarma lleva el enlace al runbook: quien despierta a las 3 a. m. no busca.
  ayuda = "Runbook: ${var.url_runbook}"
}

# ---------- Destinos: una cola de PÁGINAS (despiertan a alguien) y otra de AVISOS (se leen en horario) ----------
resource "aws_kms_key" "avisos" {
  description         = "${local.prefijo}: cifrado de los tópicos de alertas"
  enable_key_rotation = true

  # CloudWatch y EventBridge deben poder publicar en un tópico cifrado con clave propia
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "Administracion"
        Effect    = "Allow"
        Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.actual.account_id}:root" }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "ServiciosQuePublican"
        Effect    = "Allow"
        Principal = { Service = ["cloudwatch.amazonaws.com", "events.amazonaws.com"] }
        Action    = ["kms:Decrypt", "kms:GenerateDataKey*"]
        Resource  = "*"
        Condition = { StringEquals = { "aws:SourceAccount" = data.aws_caller_identity.actual.account_id } }
      }
    ]
  })
  tags = local.etiquetas
}

resource "aws_sns_topic" "pagina" {
  name              = "${local.prefijo}-pagina"
  kms_master_key_id = aws_kms_key.avisos.id
  tags              = local.etiquetas
}

resource "aws_sns_topic" "aviso" {
  name              = "${local.prefijo}-aviso"
  kms_master_key_id = aws_kms_key.avisos.id
  tags              = local.etiquetas
}

resource "aws_sns_topic_subscription" "guardia" {
  for_each  = toset(var.correos_guardia)
  topic_arn = aws_sns_topic.pagina.arn
  protocol  = "email"
  endpoint  = each.value
}

data "aws_iam_policy_document" "eventos_a_aviso" {
  statement {
    sid       = "PublicaEventBridge"
    actions   = ["sns:Publish"]
    resources = [aws_sns_topic.aviso.arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com"]
    }
    condition {
      test     = "ArnEquals"
      variable = "aws:SourceArn"
      values   = [aws_cloudwatch_event_rule.salud.arn]
    }
  }
}

resource "aws_sns_topic_policy" "aviso" {
  arn    = aws_sns_topic.aviso.arn
  policy = data.aws_iam_policy_document.eventos_a_aviso.json
}

# ---------- Síntoma 1: los clientes ven errores (tasa de 5xx del ALB) ----------
resource "aws_cloudwatch_metric_alarm" "tasa_errores" {
  alarm_name          = "${local.prefijo}-tasa-errores"
  alarm_description   = "Más del ${var.umbral_errores_pct} % de las peticiones terminan en 5xx. ${local.ayuda}#errores"
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.umbral_errores_pct
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  treat_missing_data  = "notBreaching"

  metric_query {
    id          = "tasa"
    expression  = "IF(total > 0, 100 * errores / total, 0)"
    label       = "% de 5xx"
    return_data = true
  }
  metric_query {
    id = "errores"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "HTTPCode_Target_5XX_Count"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
    }
  }
  metric_query {
    id = "total"
    metric {
      namespace   = "AWS/ApplicationELB"
      metric_name = "RequestCount"
      period      = 60
      stat        = "Sum"
      dimensions  = { LoadBalancer = var.alb_arn_suffix }
    }
  }
  tags = local.etiquetas
}

# ---------- Síntoma 2: el silencio también es un síntoma (si nadie compra, algo falla antes del ALB) ----------
resource "aws_cloudwatch_metric_alarm" "sin_trafico" {
  alarm_name          = "${local.prefijo}-sin-trafico"
  alarm_description   = "El ALB no recibe peticiones. Revisa DNS, CDN y WAF antes que la aplicación. ${local.ayuda}#silencio"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "RequestCount"
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  comparison_operator = "LessThanThreshold"
  threshold           = 1
  treat_missing_data  = "breaching" # sin datos = sin tráfico
  tags                = local.etiquetas
}

# ---------- Síntoma 3: la compra va lenta (p95, no promedio) ----------
resource "aws_cloudwatch_metric_alarm" "latencia" {
  alarm_name          = "${local.prefijo}-latencia-p95"
  alarm_description   = "p95 de TargetResponseTime por encima de ${var.latencia_p95_segundos} s. ${local.ayuda}#lentitud"
  namespace           = "AWS/ApplicationELB"
  metric_name         = "TargetResponseTime"
  dimensions          = { LoadBalancer = var.alb_arn_suffix }
  extended_statistic  = "p95"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 4
  comparison_operator = "GreaterThanThreshold"
  threshold           = var.latencia_p95_segundos
  treat_missing_data  = "notBreaching"
  tags                = local.etiquetas
}

# ---------- Síntoma 4: pedidos sin factura (cola que envejece, fallidos que se acumulan) ----------
resource "aws_cloudwatch_metric_alarm" "cola_envejece" {
  alarm_name          = "${local.prefijo}-facturacion-antiguedad"
  alarm_description   = "El mensaje más viejo de facturación espera más de 5 minutos. ${local.ayuda}#sin-factura"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateAgeOfOldestMessage"
  dimensions          = { QueueName = var.cola_facturacion }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 5
  datapoints_to_alarm = 5
  comparison_operator = "GreaterThanThreshold"
  threshold           = 300
  treat_missing_data  = "notBreaching"
  tags                = local.etiquetas
}

resource "aws_cloudwatch_metric_alarm" "dlq_con_mensajes" {
  alarm_name          = "${local.prefijo}-facturacion-dlq"
  alarm_description   = "Hay mensajes en la cola de fallidos. Lee el motivo y reprocesa con procedimiento. ${local.ayuda}#sin-factura"
  namespace           = "AWS/SQS"
  metric_name         = "ApproximateNumberOfMessagesVisible"
  dimensions          = { QueueName = var.dlq_facturacion }
  statistic           = "Maximum"
  period              = 60
  evaluation_periods  = 1
  datapoints_to_alarm = 1
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  tags                = local.etiquetas
}

# ---------- Síntoma 5: salidas a Internet que fallan sin que nada se haya desplegado ----------
resource "aws_cloudwatch_metric_alarm" "nat_puertos" {
  alarm_name          = "${local.prefijo}-nat-puertos"
  alarm_description   = "La NAT no encuentra puertos libres (ErrorPortAllocation). Conexiones sin reutilizar o demasiado tráfico a un mismo destino. ${local.ayuda}#nat"
  namespace           = "AWS/NATGateway"
  metric_name         = "ErrorPortAllocation"
  dimensions          = { NatGatewayId = var.nat_gateway_id }
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 2
  comparison_operator = "GreaterThanThreshold"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  tags                = local.etiquetas
}

# ---------- La sonda sintética escribe líneas "sonda.dependencia … ok=false": se convierten en métrica ----------
resource "aws_cloudwatch_log_metric_filter" "sonda_falla" {
  name           = "${local.prefijo}-sonda-dependencia-fallida"
  log_group_name = var.grupo_logs_app
  pattern        = "\"sonda.dependencia\" \"ok=false\""

  metric_transformation {
    name          = "DependenciaFallida"
    namespace     = "ModaLima/Sonda"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "sonda" {
  alarm_name          = "${local.prefijo}-sonda-dependencia"
  alarm_description   = "Una dependencia falla desde la propia aplicación (3 minutos seguidos). Consulta el informe de la sonda. ${local.ayuda}#sonda"
  namespace           = "ModaLima/Sonda"
  metric_name         = "DependenciaFallida"
  statistic           = "Sum"
  period              = 60
  evaluation_periods  = 3
  datapoints_to_alarm = 3
  comparison_operator = "GreaterThanOrEqualToThreshold"
  threshold           = 1
  treat_missing_data  = "notBreaching"
  tags                = local.etiquetas
}

# ---------- Una sola PÁGINA por incidente: la alarma compuesta evita siete correos a la vez ----------
resource "aws_cloudwatch_composite_alarm" "no_se_puede_comprar" {
  alarm_name        = "${local.prefijo}-no-se-puede-comprar"
  alarm_description = "Los clientes no pueden comprar (errores, silencio o dependencia caída). Severidad 1. ${local.ayuda}#declarar"
  alarm_rule = join(" OR ", [
    "ALARM(${aws_cloudwatch_metric_alarm.tasa_errores.alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.sin_trafico.alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.sonda.alarm_name})"
  ])
  alarm_actions = [aws_sns_topic.pagina.arn]
  ok_actions    = [aws_sns_topic.pagina.arn]
  tags          = local.etiquetas
}

resource "aws_cloudwatch_composite_alarm" "degradacion" {
  alarm_name        = "${local.prefijo}-degradacion"
  alarm_description = "Degradación sin caída total (lentitud, facturas atrasadas, NAT). Severidad 2-3. ${local.ayuda}"
  alarm_rule = join(" OR ", [
    "ALARM(${aws_cloudwatch_metric_alarm.latencia.alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.cola_envejece.alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.dlq_con_mensajes.alarm_name})",
    "ALARM(${aws_cloudwatch_metric_alarm.nat_puertos.alarm_name})"
  ])
  alarm_actions = [aws_sns_topic.aviso.arn]
  tags          = local.etiquetas
}

# ---------- Eventos de AWS Health que afectan a tu cuenta: ¿es nuestro o del proveedor? ----------
resource "aws_cloudwatch_event_rule" "salud" {
  name        = "${local.prefijo}-aws-health"
  description = "Eventos de AWS Health de la cuenta (incidentes y mantenimientos)"
  event_pattern = jsonencode({
    source        = ["aws.health"]
    "detail-type" = ["AWS Health Event"]
  })
  tags = local.etiquetas
}

resource "aws_cloudwatch_event_target" "salud_a_aviso" {
  rule = aws_cloudwatch_event_rule.salud.name
  arn  = aws_sns_topic.aviso.arn
}

# ---------- Panel: tráfico, errores, latencia, saturación ----------
resource "aws_cloudwatch_dashboard" "tienda" {
  dashboard_name = "${local.prefijo}-incidentes"
  dashboard_body = jsonencode({
    widgets = [
      {
        type = "metric", x = 0, y = 0, width = 12, height = 6
        properties = {
          title  = "Tráfico y errores 5xx por minuto"
          region = var.region
          stat   = "Sum"
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "RequestCount", "LoadBalancer", var.alb_arn_suffix],
            [".", "HTTPCode_Target_5XX_Count", ".", ".", { color = "#d62728" }],
            [".", "HTTPCode_ELB_5XX_Count", ".", ".", { color = "#ff7f0e" }]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 0, width = 12, height = 6
        properties = {
          title  = "Latencia p50 / p95 / p99"
          region = var.region
          period = 60
          metrics = [
            ["AWS/ApplicationELB", "TargetResponseTime", "LoadBalancer", var.alb_arn_suffix, { stat = "p50" }],
            ["...", { stat = "p95" }],
            ["...", { stat = "p99" }]
          ]
        }
      },
      {
        type = "metric", x = 0, y = 6, width = 12, height = 6
        properties = {
          title  = "Facturación: antigüedad del mensaje más viejo y fallidos"
          region = var.region
          period = 60
          metrics = [
            ["AWS/SQS", "ApproximateAgeOfOldestMessage", "QueueName", var.cola_facturacion, { stat = "Maximum" }],
            ["AWS/SQS", "ApproximateNumberOfMessagesVisible", "QueueName", var.dlq_facturacion, { stat = "Maximum", yAxis = "right" }]
          ]
        }
      },
      {
        type = "metric", x = 12, y = 6, width = 12, height = 6
        properties = {
          title  = "Saturación de salida: puertos NAT y sonda"
          region = var.region
          period = 60
          stat   = "Sum"
          metrics = [
            ["AWS/NATGateway", "ErrorPortAllocation", "NatGatewayId", var.nat_gateway_id],
            ["ModaLima/Sonda", "DependenciaFallida"]
          ]
        }
      },
      {
        type = "alarm", x = 0, y = 12, width = 24, height = 3
        properties = {
          title = "Estado de las alarmas"
          alarms = [
            aws_cloudwatch_composite_alarm.no_se_puede_comprar.arn,
            aws_cloudwatch_composite_alarm.degradacion.arn
          ]
        }
      }
    ]
  })
}

# ---------- Consultas guardadas de Logs Insights (para no escribirlas con prisa) ----------
resource "aws_cloudwatch_query_definition" "errores_por_minuto" {
  name            = "${local.prefijo}/1-errores-por-minuto"
  log_group_names = [var.grupo_logs_app]
  query_string    = <<-EOT
    fields @timestamp, nivel, operacion
    | filter nivel = "ERROR"
    | stats count(*) as errores by bin(1m)
    | sort @timestamp desc
  EOT
}

resource "aws_cloudwatch_query_definition" "excepciones_frecuentes" {
  name            = "${local.prefijo}/2-excepciones-frecuentes"
  log_group_names = [var.grupo_logs_app]
  query_string    = <<-EOT
    fields excepcion, operacion
    | filter nivel = "ERROR"
    | stats count(*) as veces, count_distinct(idTraza) as peticiones by excepcion, operacion
    | sort veces desc
    | limit 20
  EOT
}

resource "aws_cloudwatch_query_definition" "lentas_por_operacion" {
  name            = "${local.prefijo}/3-latencia-por-operacion"
  log_group_names = [var.grupo_logs_app]
  query_string    = <<-EOT
    fields operacion, duracionMs
    | filter ispresent(duracionMs)
    | stats count(*) as llamadas, pct(duracionMs, 50) as p50, pct(duracionMs, 95) as p95, max(duracionMs) as maximo by operacion
    | sort p95 desc
  EOT
}

resource "aws_cloudwatch_query_definition" "traza_de_una_peticion" {
  name            = "${local.prefijo}/4-traza-de-una-peticion"
  log_group_names = [var.grupo_logs_app]
  query_string    = <<-EOT
    fields @timestamp, nivel, operacion, mensaje
    | filter idTraza = "PEGA-AQUI-EL-ID"
    | sort @timestamp asc
  EOT
}

resource "aws_cloudwatch_query_definition" "sonda" {
  name            = "${local.prefijo}/5-sonda-dependencias"
  log_group_names = [var.grupo_logs_app]
  query_string    = <<-EOT
    fields @timestamp, @message
    | filter @message like "sonda.dependencia"
    | parse @message "dependencia=* escalon=* ok=* ms=*" as dependencia, escalon, ok, ms
    | stats count(*) as pruebas, sum(ok = "false") as fallos, max(ms) as maximoMs by dependencia, escalon
    | sort fallos desc
  EOT
}

output "topico_pagina" {
  value = aws_sns_topic.pagina.arn
}

output "panel" {
  value = "https://${var.region}.console.aws.amazon.com/cloudwatch/home?region=${var.region}#dashboards/dashboard/${aws_cloudwatch_dashboard.tienda.dashboard_name}"
}
