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

variable "imagen" {
  type = string
}

variable "subredes_privadas" {
  description = "Indícalas siempre: sin ellas Express usa la VPC por defecto (subredes públicas)."
  type        = list(string)
}

variable "grupos_seguridad" {
  type    = list(string)
  default = []
}

variable "secreto_db_arn" {
  type = string
}

variable "politica_infraestructura_arn" {
  description = "Política administrada del rol de infraestructura (verifica el ARN exacto en la documentación)."
  type        = string
  default     = "arn:aws:iam::aws:policy/service-role/AmazonECSInfrastructureRoleforExpressGatewayServices"
}

locals {
  nombre = "${var.entorno}-pedidos"
}

data "aws_iam_policy_document" "confianza_ecs" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs.amazonaws.com"]
    }
  }
}

data "aws_iam_policy_document" "confianza_tareas" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Rol de infraestructura: lo usa ECS para crear el ALB, certificados y escalado
resource "aws_iam_role" "infraestructura" {
  name               = "${local.nombre}-express-infraestructura"
  assume_role_policy = data.aws_iam_policy_document.confianza_ecs.json
}

resource "aws_iam_role_policy_attachment" "infraestructura" {
  role       = aws_iam_role.infraestructura.name
  policy_arn = var.politica_infraestructura_arn
}

# Rol de ejecución: imagen, logs y secretos inyectados
resource "aws_iam_role" "ejecucion" {
  name               = "${local.nombre}-ejecucion"
  assume_role_policy = data.aws_iam_policy_document.confianza_tareas.json
}

resource "aws_iam_role_policy_attachment" "ejecucion" {
  role       = aws_iam_role.ejecucion.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ejecucion_secretos" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.secreto_db_arn]
  }
}

resource "aws_iam_role_policy" "ejecucion_secretos" {
  name   = "lee-secretos-inyectados"
  role   = aws_iam_role.ejecucion.id
  policy = data.aws_iam_policy_document.ejecucion_secretos.json
}

# Rol de tarea: debe existir ANTES de crear el servicio
resource "aws_iam_role" "tarea" {
  name               = "${local.nombre}-tarea"
  assume_role_policy = data.aws_iam_policy_document.confianza_tareas.json
}

resource "aws_ecs_express_gateway_service" "pedidos" {
  service_name            = "pedidos"
  execution_role_arn      = aws_iam_role.ejecucion.arn
  infrastructure_role_arn = aws_iam_role.infraestructura.arn
  task_role_arn           = aws_iam_role.tarea.arn
  health_check_path       = "/actuator/health/readiness"
  cpu                     = "1024"
  memory                  = "2048"

  primary_container {
    image          = var.imagen
    container_port = 8080

    environment {
      name  = "SERVER_SHUTDOWN"
      value = "graceful"
    }

    environment {
      name  = "JAVA_TOOL_OPTIONS"
      value = "-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError"
    }

    secret {
      name       = "DB_SECRETO"
      value_from = var.secreto_db_arn
    }
  }

  network_configuration {
    subnets         = var.subredes_privadas
    security_groups = var.grupos_seguridad
  }

  scaling_target {
    min_task_count            = 2
    max_task_count            = 10
    auto_scaling_metric       = "AVERAGE_CPU"
    auto_scaling_target_value = 60
  }

  # Las etiquetas solo se pueden fijar al crear
  tags = {
    equipo  = "pedidos"
    entorno = var.entorno
  }

  depends_on = [
    aws_iam_role_policy_attachment.infraestructura,
    aws_iam_role_policy_attachment.ejecucion,
  ]
}

output "endpoints" {
  value = aws_ecs_express_gateway_service.pedidos.ingress_paths
}
