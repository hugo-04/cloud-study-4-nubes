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

variable "subredes_publicas" {
  type = list(string)
}

variable "subredes_privadas" {
  type = list(string)
}

variable "dominio" {
  description = "Dominio de la API, p. ej. api.modalima.com"
  type        = string
}

variable "zona_route53_id" {
  type = string
}

variable "bucket_logs" {
  description = "Bucket S3 para los logs de acceso (con la política que permite al servicio escribir)."
  type        = string
}

locals {
  nombre = "${var.entorno}-tienda"
}

# ---------- Certificado en ACM, validado por DNS ----------
resource "aws_acm_certificate" "api" {
  domain_name       = var.dominio
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "validacion" {
  for_each = {
    for o in aws_acm_certificate.api.domain_validation_options : o.domain_name => {
      nombre = o.resource_record_name
      tipo   = o.resource_record_type
      valor  = o.resource_record_value
    }
  }

  zone_id = var.zona_route53_id
  name    = each.value.nombre
  type    = each.value.tipo
  records = [each.value.valor]
  ttl     = 60
}

resource "aws_acm_certificate_validation" "api" {
  certificate_arn         = aws_acm_certificate.api.arn
  validation_record_fqdns = [for r in aws_route53_record.validacion : r.fqdn]
}

# ---------- Security groups ----------
resource "aws_security_group" "alb" {
  name_prefix = "${local.nombre}-alb-"
  description = "ALB publico: 80 y 443 desde Internet"
  vpc_id      = var.vpc_id

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_vpc_security_group_ingress_rule" "alb_https" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 443
  to_port           = 443
  ip_protocol       = "tcp"
}

resource "aws_vpc_security_group_ingress_rule" "alb_http" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "0.0.0.0/0"
  from_port         = 80
  to_port           = 80
  ip_protocol       = "tcp"
  description       = "Solo para redirigir a HTTPS"
}

resource "aws_vpc_security_group_egress_rule" "alb_a_tareas" {
  security_group_id = aws_security_group.alb.id
  cidr_ipv4         = "10.0.0.0/8"
  from_port         = 8080
  to_port           = 8080
  ip_protocol       = "tcp"
  description       = "Hacia las tareas"
}

# ---------- ALB ----------
resource "aws_lb" "publico" {
  name                       = "${local.nombre}-publico"
  load_balancer_type         = "application"
  internal                   = false
  security_groups            = [aws_security_group.alb.id]
  subnets                    = var.subredes_publicas
  idle_timeout               = 60
  drop_invalid_header_fields = true
  enable_deletion_protection = true
  desync_mitigation_mode     = "strictest"

  access_logs {
    bucket  = var.bucket_logs
    prefix  = "alb/${local.nombre}"
    enabled = true
  }
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.publico.arn
  port              = 80
  protocol          = "HTTP"

  default_action {
    type = "redirect"

    redirect {
      port        = "443"
      protocol    = "HTTPS"
      status_code = "HTTP_301"
    }
  }
}

resource "aws_lb_listener" "https" {
  load_balancer_arn = aws_lb.publico.arn
  port              = 443
  protocol          = "HTTPS"
  ssl_policy        = "ELBSecurityPolicy-TLS13-1-2-2021-06"
  certificate_arn   = aws_acm_certificate_validation.api.certificate_arn

  default_action {
    type = "fixed-response"

    fixed_response {
      content_type = "application/json"
      message_body = "{\"error\":\"ruta no encontrada\"}"
      status_code  = "404"
    }
  }
}

# ---------- Target groups (tipo ip: Fargate / EKS) ----------
resource "aws_lb_target_group" "pedidos" {
  name                 = "${local.nombre}-pedidos"
  port                 = 8080
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path                = "/actuator/health/readiness"
    matcher             = "200"
    interval            = 15
    timeout             = 5
    healthy_threshold   = 2
    unhealthy_threshold = 3
  }
}

resource "aws_lb_target_group" "pedidos_canary" {
  name                 = "${local.nombre}-pedidos-c"
  port                 = 8080
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path    = "/actuator/health/readiness"
    matcher = "200"
  }
}

resource "aws_lb_target_group" "facturas" {
  name                 = "${local.nombre}-facturas"
  port                 = 8080
  protocol             = "HTTP"
  target_type          = "ip"
  vpc_id               = var.vpc_id
  deregistration_delay = 30

  health_check {
    path    = "/actuator/health/readiness"
    matcher = "200"
  }
}

# ---------- Reglas por ruta, con reparto ponderado para canary ----------
resource "aws_lb_listener_rule" "pedidos" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 10

  action {
    type = "forward"

    forward {
      target_group {
        arn    = aws_lb_target_group.pedidos.arn
        weight = 90
      }

      target_group {
        arn    = aws_lb_target_group.pedidos_canary.arn
        weight = 10
      }
    }
  }

  condition {
    path_pattern {
      values = ["/pedidos", "/pedidos/*"]
    }
  }
}

resource "aws_lb_listener_rule" "facturas" {
  listener_arn = aws_lb_listener.https.arn
  priority     = 20

  action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.facturas.arn
  }

  condition {
    path_pattern {
      values = ["/facturas", "/facturas/*"]
    }
  }
}

# ---------- DNS: alias al ALB (nunca una IP) ----------
resource "aws_route53_record" "api" {
  zone_id = var.zona_route53_id
  name    = var.dominio
  type    = "A"

  alias {
    name                   = aws_lb.publico.dns_name
    zone_id                = aws_lb.publico.zone_id
    evaluate_target_health = true
  }
}

# ---------- NLB interno con IP estática por zona (ejemplo para un broker TCP) ----------
resource "aws_lb" "tcp" {
  name               = "${local.nombre}-tcp"
  load_balancer_type = "network"
  internal           = true

  dynamic "subnet_mapping" {
    for_each = var.subredes_privadas

    content {
      subnet_id = subnet_mapping.value
    }
  }

  enable_cross_zone_load_balancing = true
}

resource "aws_lb_target_group" "broker" {
  name        = "${local.nombre}-broker"
  port        = 9094
  protocol    = "TCP"
  target_type = "ip"
  vpc_id      = var.vpc_id

  health_check {
    protocol = "TCP"
  }
}

resource "aws_lb_listener" "broker" {
  load_balancer_arn = aws_lb.tcp.arn
  port              = 9094
  protocol          = "TCP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.broker.arn
  }
}

output "alb_dns" {
  value = aws_lb.publico.dns_name
}

output "sg_alb_id" {
  value = aws_security_group.alb.id
}

output "target_group_pedidos_arn" {
  value = aws_lb_target_group.pedidos.arn
}
