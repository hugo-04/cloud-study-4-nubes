terraform {
  required_version = ">= 1.6"
  # backend "<tipo>" { ... }  ← cada nube: ver su capítulo 10
}

variable "entorno" {
  type    = string
  default = "dev"
}

module "pedidos" {
  source   = "../modulos/servicio"
  nombre   = "pedidos"
  entorno  = var.entorno
  replicas = var.entorno == "prod" ? 3 : 1
  colas    = ["facturacion", "despacho"]
}

# Renombrado sin destruir (antes se llamaba module.ordenes)
moved {
  from = module.ordenes
  to   = module.pedidos
}

check "colas_esperadas" {
  assert {
    condition     = length(module.pedidos.colas) == 2
    error_message = "pedidos debería tener 2 colas."
  }
}

output "pedidos" {
  value = module.pedidos.id
}
