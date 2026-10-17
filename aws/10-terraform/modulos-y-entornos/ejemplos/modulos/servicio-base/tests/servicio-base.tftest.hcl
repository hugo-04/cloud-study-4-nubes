# Pruebas del módulo: no crean nada en AWS (proveedor simulado).
mock_provider "aws" {}

variables {
  nombre  = "pedidos"
  entorno = "dev"
  dueno   = "equipo-pedidos@modalima.example"
  equipo  = "pedidos"
}

run "nombres_y_etiquetas" {
  command = plan

  assert {
    condition     = aws_sqs_queue.principal.name == "dev-pedidos" && aws_sqs_queue.dlq.name == "dev-pedidos-dlq"
    error_message = "Los nombres deben ser <entorno>-<nombre> y <entorno>-<nombre>-dlq."
  }

  assert {
    condition     = aws_sqs_queue.principal.tags["equipo"] == "pedidos" && aws_sqs_queue.principal.tags["gestionado_por"] == "terraform"
    error_message = "Faltan las etiquetas obligatorias."
  }

  assert {
    condition     = aws_cloudwatch_log_group.app.retention_in_days == 30
    error_message = "La retención de logs por defecto debe ser de 30 días."
  }
}

run "el_cifrado_siempre_esta_activo" {
  command = plan

  assert {
    condition     = aws_sqs_queue.principal.sqs_managed_sse_enabled && aws_sqs_queue.dlq.sqs_managed_sse_enabled
    error_message = "Las colas deben cifrarse siempre."
  }
}

run "etiquetas_extra_no_pisan_las_obligatorias" {
  command = plan

  variables {
    etiquetas_extra = { equipo = "otro", centro_costo = "cc-42" }
  }

  assert {
    condition     = aws_sqs_queue.principal.tags["equipo"] == "pedidos" && aws_sqs_queue.principal.tags["centro_costo"] == "cc-42"
    error_message = "Las etiquetas obligatorias tienen prioridad sobre las extra."
  }
}

run "rechaza_nombre_invalido" {
  command = plan

  variables {
    nombre = "Pedidos_X"
  }

  expect_failures = [var.nombre]
}

run "rechaza_retencion_de_logs_invalida" {
  command = plan

  variables {
    retencion_logs_dias = 45
  }

  expect_failures = [var.retencion_logs_dias]
}

run "prod_exige_limite_de_permisos" {
  command = plan

  variables {
    entorno = "prod"
  }

  expect_failures = [aws_iam_role.tarea]
}

run "prod_con_limite_es_valido" {
  command = plan

  variables {
    entorno             = "prod"
    arn_limite_permisos = "arn:aws:iam::111122223333:policy/limite-permisos-aplicaciones"
  }

  assert {
    condition     = aws_iam_role.tarea.permissions_boundary == "arn:aws:iam::111122223333:policy/limite-permisos-aplicaciones"
    error_message = "El rol debe llevar el límite de permisos."
  }
}
