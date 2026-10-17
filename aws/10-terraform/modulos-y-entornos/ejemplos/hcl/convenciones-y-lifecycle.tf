# Fragmentos de referencia (no se aplican tal cual).

# 1) Renombrar un módulo sin destruir lo que contiene.
moved {
  from = module.cola
  to   = module.servicio
}

# 2) De count (por posición) a for_each (por clave estable): una dirección movida por servicio.
moved {
  from = module.servicio[0]
  to   = module.servicio["catalogo"]
}

# 3) lifecycle: proteger lo que no se debe perder.
resource "aws_dynamodb_table" "pedidos" {
  name         = "prod-pedidos"
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "pk"

  attribute {
    name = "pk"
    type = "S"
  }

  lifecycle {
    prevent_destroy = true # un plan que destruya esta tabla falla antes de empezar
  }
}

# 4) ignore_changes: lo que otro sistema (por ejemplo, el autoescalado) modifica a propósito.
resource "aws_ecs_service" "api" {
  name            = "prod-api"
  cluster         = "prod"
  task_definition = "api:1"
  desired_count   = 2

  lifecycle {
    ignore_changes = [desired_count]
  }
}

# 5) check: reglas de higiene que avisan sin bloquear.
check "etiquetas_obligatorias" {
  assert {
    condition     = alltrue([for k, s in var.servicios : s.dueno != ""])
    error_message = "Todos los servicios deben tener dueño."
  }
}

# 6) Versión fija del módulo (Git) en cada consumidor.
module "servicio_remoto" {
  source = "git::https://github.com/modalima/modulos.git//servicio-base?ref=v1.3.0"

  nombre  = "catalogo"
  entorno = "dev"
  dueno   = "equipo-catalogo@modalima.example"
  equipo  = "catalogo"
}
