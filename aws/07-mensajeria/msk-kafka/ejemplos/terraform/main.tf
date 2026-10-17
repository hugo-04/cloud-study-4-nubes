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

variable "subnet_ids" {
  type        = list(string)
  description = "Tres subredes privadas, una por zona de disponibilidad"
}

variable "sg_clientes" {
  type        = string
  description = "Grupo de seguridad de los servicios que producen y consumen"
}

variable "kafka_version" {
  type        = string
  default     = "3.8.x"
  description = "Versión de Kafka (verifica las vigentes en MSK)"
}

data "aws_caller_identity" "actual" {}

resource "aws_kms_key" "msk" {
  description         = "Cifrado en reposo del clúster MSK ${var.entorno}"
  enable_key_rotation = true
}

resource "aws_security_group" "msk" {
  name        = "${var.entorno}-msk"
  description = "Brokers MSK: IAM (9098) solo desde los clientes"
  vpc_id      = var.vpc_id
}

resource "aws_vpc_security_group_ingress_rule" "iam" {
  security_group_id            = aws_security_group.msk.id
  referenced_security_group_id = var.sg_clientes
  ip_protocol                  = "tcp"
  from_port                    = 9098
  to_port                      = 9098
  description                  = "Clientes con autenticación IAM"
}

# Configuración de los brokers: nada de tópicos automáticos, durabilidad por defecto
resource "aws_msk_configuration" "pedidos" {
  name           = "${var.entorno}-pedidos"
  kafka_versions = [var.kafka_version]

  server_properties = <<-EOT
    auto.create.topics.enable=false
    default.replication.factor=3
    min.insync.replicas=2
    num.partitions=6
    log.retention.hours=72
    delete.topic.enable=true
  EOT
}

resource "aws_cloudwatch_log_group" "msk" {
  name              = "/msk/${var.entorno}-pedidos"
  retention_in_days = 30
}

# --- Clúster aprovisionado: 3 brokers en 3 zonas, IAM y TLS ---
resource "aws_msk_cluster" "pedidos" {
  cluster_name           = "${var.entorno}-pedidos"
  kafka_version          = var.kafka_version
  number_of_broker_nodes = 3
  enhanced_monitoring    = "PER_BROKER"

  broker_node_group_info {
    instance_type   = "kafka.m7g.large"
    client_subnets  = var.subnet_ids
    security_groups = [aws_security_group.msk.id]

    storage_info {
      ebs_storage_info {
        volume_size = 200
      }
    }
  }

  client_authentication {
    sasl {
      iam = true
    }
  }

  encryption_info {
    encryption_at_rest_kms_key_arn = aws_kms_key.msk.arn
    encryption_in_transit {
      client_broker = "TLS"
      in_cluster    = true
    }
  }

  configuration_info {
    arn      = aws_msk_configuration.pedidos.arn
    revision = aws_msk_configuration.pedidos.latest_revision
  }

  logging_info {
    broker_logs {
      cloudwatch_logs {
        enabled   = true
        log_group = aws_cloudwatch_log_group.msk.name
      }
    }
  }
}

# --- Piloto: MSK Serverless (solo IAM) ---
resource "aws_msk_serverless_cluster" "piloto" {
  cluster_name = "${var.entorno}-piloto"

  vpc_config {
    subnet_ids         = var.subnet_ids
    security_group_ids = [aws_security_group.msk.id]
  }

  client_authentication {
    sasl {
      iam {
        enabled = true
      }
    }
  }
}

# --- Alarma de disco por broker ---
resource "aws_cloudwatch_metric_alarm" "disco" {
  for_each            = toset(["1", "2", "3"])
  alarm_name          = "${var.entorno}-msk-disco-broker-${each.key}"
  namespace           = "AWS/Kafka"
  metric_name         = "KafkaDataLogsDiskUsed"
  dimensions          = { "Cluster Name" = aws_msk_cluster.pedidos.cluster_name, "Broker ID" = each.key }
  statistic           = "Maximum"
  period              = 300
  evaluation_periods  = 3
  threshold           = 70
  comparison_operator = "GreaterThanThreshold"
  treat_missing_data  = "notBreaching"
}

# --- Permisos IAM de los servicios (clúster, tópico y grupo) ---
locals {
  arn_topicos = "${replace(aws_msk_cluster.pedidos.arn, ":cluster/", ":topic/")}/pedidos.*"
  arn_grupos  = "${replace(aws_msk_cluster.pedidos.arn, ":cluster/", ":group/")}/facturacion*"
}

data "aws_iam_policy_document" "productor" {
  statement {
    actions   = ["kafka-cluster:Connect", "kafka-cluster:DescribeCluster"]
    resources = [aws_msk_cluster.pedidos.arn]
  }
  statement {
    actions   = ["kafka-cluster:DescribeTopic", "kafka-cluster:WriteData", "kafka-cluster:WriteDataIdempotently"]
    resources = [local.arn_topicos]
  }
}

data "aws_iam_policy_document" "consumidor" {
  statement {
    actions   = ["kafka-cluster:Connect", "kafka-cluster:DescribeCluster"]
    resources = [aws_msk_cluster.pedidos.arn]
  }
  statement {
    actions   = ["kafka-cluster:DescribeTopic", "kafka-cluster:ReadData"]
    resources = [local.arn_topicos]
  }
  statement {
    actions   = ["kafka-cluster:DescribeGroup", "kafka-cluster:AlterGroup"]
    resources = [local.arn_grupos]
  }
}

output "cluster_arn" {
  value = aws_msk_cluster.pedidos.arn
}

output "politica_consumidor_json" {
  value = data.aws_iam_policy_document.consumidor.json
}

output "politica_productor_json" {
  value = data.aws_iam_policy_document.productor.json
}
