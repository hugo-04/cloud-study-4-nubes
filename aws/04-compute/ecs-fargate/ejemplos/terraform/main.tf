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

variable "vpc_id" {
  type = string
}

variable "subredes_privadas" {
  type = list(string)
}

variable "sg_balanceador_id" {
  description = "Security group del ALB (único origen permitido hacia las tareas)."
  type        = string
}

variable "target_group_arn" {
  type = string
}

variable "imagen" {
  description = "Imagen por digest: <cuenta>.dkr.ecr.<region>.amazonaws.com/pedidos@sha256:..."
  type        = string
}

variable "secreto_db_arn" {
  type = string
}

variable "clave_kms_arn" {
  description = "CMK con la que se cifran el secreto y los logs."
  type        = string
}

variable "minimo" {
  type    = number
  default = 2
}

variable "maximo" {
  type    = number
  default = 10
}

locals {
  nombre = "${var.entorno}-pedidos"
}

# ---------- Cluster y capacidad ----------
resource "aws_ecs_cluster" "este" {
  name = var.entorno

  setting {
    name  = "containerInsights"
    value = "enhanced"
  }
}

resource "aws_ecs_cluster_capacity_providers" "este" {
  cluster_name       = aws_ecs_cluster.este.name
  capacity_providers = ["FARGATE", "FARGATE_SPOT"]
}

# ---------- Logs ----------
resource "aws_cloudwatch_log_group" "pedidos" {
  name              = "/ecs/${var.entorno}/pedidos"
  retention_in_days = 30
  kms_key_id        = var.clave_kms_arn
}

# ---------- Roles ----------
data "aws_iam_policy_document" "confianza" {
  statement {
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["ecs-tasks.amazonaws.com"]
    }
  }
}

# Rol de EJECUCIÓN: lo usa ECS para arrancar la tarea
resource "aws_iam_role" "ejecucion" {
  name               = "${local.nombre}-ejecucion"
  assume_role_policy = data.aws_iam_policy_document.confianza.json
}

resource "aws_iam_role_policy_attachment" "ejecucion_base" {
  role       = aws_iam_role.ejecucion.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}

data "aws_iam_policy_document" "ejecucion_secretos" {
  statement {
    actions   = ["secretsmanager:GetSecretValue"]
    resources = [var.secreto_db_arn]
  }

  statement {
    actions   = ["kms:Decrypt"]
    resources = [var.clave_kms_arn]
  }
}

resource "aws_iam_role_policy" "ejecucion_secretos" {
  name   = "lee-secretos-inyectados"
  role   = aws_iam_role.ejecucion.id
  policy = data.aws_iam_policy_document.ejecucion_secretos.json
}

# Rol de TAREA: lo usa el código de la aplicación (mínimo privilegio)
resource "aws_iam_role" "tarea" {
  name               = "${local.nombre}-tarea"
  assume_role_policy = data.aws_iam_policy_document.confianza.json
}

data "aws_iam_policy_document" "tarea" {
  statement {
    sid       = "LeerSuConfiguracion"
    actions   = ["ssm:GetParametersByPath"]
    resources = ["arn:aws:ssm:${var.region}:*:parameter/${var.entorno}/pedidos/*"]
  }

  # Necesario para ECS Exec
  statement {
    sid       = "EcsExec"
    actions   = ["ssmmessages:CreateControlChannel", "ssmmessages:CreateDataChannel", "ssmmessages:OpenControlChannel", "ssmmessages:OpenDataChannel"]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "tarea" {
  name   = "permisos-de-la-aplicacion"
  role   = aws_iam_role.tarea.id
  policy = data.aws_iam_policy_document.tarea.json
}

# ---------- Red de la tarea ----------
resource "aws_security_group" "tarea" {
  name_prefix = "${local.nombre}-"
  description = "Tareas de pedidos: entrada solo desde el balanceador"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "desde_alb" {
  security_group_id            = aws_security_group.tarea.id
  referenced_security_group_id = var.sg_balanceador_id
  from_port                    = 8080
  to_port                      = 8080
  ip_protocol                  = "tcp"
  description                  = "ALB hacia la aplicacion"
}

resource "aws_vpc_security_group_egress_rule" "salida_https" {
  security_group_id = aws_security_group.tarea.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
  description       = "HTTPS hacia endpoints de AWS"
}

# ---------- Definición de la tarea ----------
resource "aws_ecs_task_definition" "pedidos" {
  family                   = local.nombre
  requires_compatibilities = ["FARGATE"]
  network_mode             = "awsvpc"
  cpu                      = 1024
  memory                   = 2048
  execution_role_arn       = aws_iam_role.ejecucion.arn
  task_role_arn            = aws_iam_role.tarea.arn

  runtime_platform {
    cpu_architecture        = "ARM64"
    operating_system_family = "LINUX"
  }

  container_definitions = jsonencode([
    {
      name         = "app"
      image        = var.imagen
      essential    = true
      portMappings = [{ containerPort = 8080, protocol = "tcp" }]
      environment = [
        { name = "JAVA_TOOL_OPTIONS", value = "-XX:MaxRAMPercentage=75 -XX:+ExitOnOutOfMemoryError" },
        { name = "SERVER_SHUTDOWN", value = "graceful" },
        { name = "CONFIG_RUTA", value = "/${var.entorno}/pedidos" },
      ]
      secrets                = [{ name = "DB_SECRETO", valueFrom = var.secreto_db_arn }]
      stopTimeout            = 60
      readonlyRootFilesystem = true
      linuxParameters        = { initProcessEnabled = true }
      healthCheck = {
        command     = ["CMD-SHELL", "wget -qO- http://localhost:8080/actuator/health/liveness || exit 1"]
        interval    = 15
        timeout     = 5
        retries     = 3
        startPeriod = 90
      }
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group"         = aws_cloudwatch_log_group.pedidos.name
          "awslogs-region"        = var.region
          "awslogs-stream-prefix" = "app"
        }
      }
    }
  ])
}

# ---------- Servicio ----------
resource "aws_ecs_service" "pedidos" {
  name                               = "pedidos"
  cluster                            = aws_ecs_cluster.este.id
  task_definition                    = aws_ecs_task_definition.pedidos.arn
  desired_count                      = var.minimo
  health_check_grace_period_seconds  = 120
  enable_execute_command             = true
  deployment_minimum_healthy_percent = 100
  deployment_maximum_percent         = 200

  # Mínimo estable en Fargate; el exceso, en Spot
  capacity_provider_strategy {
    capacity_provider = "FARGATE"
    base              = 1
    weight            = 1
  }

  capacity_provider_strategy {
    capacity_provider = "FARGATE_SPOT"
    weight            = 3
  }

  network_configuration {
    subnets          = var.subredes_privadas
    security_groups  = [aws_security_group.tarea.id]
    assign_public_ip = false
  }

  load_balancer {
    target_group_arn = var.target_group_arn
    container_name   = "app"
    container_port   = 8080
  }

  deployment_circuit_breaker {
    enable   = true
    rollback = true
  }

  lifecycle {
    ignore_changes = [desired_count] # lo gobierna el autoescalado
  }

  depends_on = [aws_ecs_cluster_capacity_providers.este]
}

# ---------- Autoescalado ----------
resource "aws_appautoscaling_target" "pedidos" {
  service_namespace  = "ecs"
  resource_id        = "service/${aws_ecs_cluster.este.name}/${aws_ecs_service.pedidos.name}"
  scalable_dimension = "ecs:service:DesiredCount"
  min_capacity       = var.minimo
  max_capacity       = var.maximo
}

resource "aws_appautoscaling_policy" "cpu" {
  name               = "${local.nombre}-cpu"
  policy_type        = "TargetTrackingScaling"
  service_namespace  = aws_appautoscaling_target.pedidos.service_namespace
  resource_id        = aws_appautoscaling_target.pedidos.resource_id
  scalable_dimension = aws_appautoscaling_target.pedidos.scalable_dimension

  target_tracking_scaling_policy_configuration {
    target_value       = 60
    scale_in_cooldown  = 300
    scale_out_cooldown = 60

    predefined_metric_specification {
      predefined_metric_type = "ECSServiceAverageCPUUtilization"
    }
  }
}

output "servicio" {
  value = aws_ecs_service.pedidos.name
}

output "rol_tarea_arn" {
  value = aws_iam_role.tarea.arn
}
