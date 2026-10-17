# terraform test (desde ejemplos/raiz)
run "dev_con_dos_colas" {
  command = plan

  variables {
    entorno = "dev"
  }

  assert {
    condition     = length(module.pedidos.colas) == 2
    error_message = "se esperaban 2 colas"
  }
}

run "prod_usa_tres_replicas" {
  command = plan

  variables {
    entorno = "prod"
  }

  assert {
    condition     = module.pedidos.replicas == 3
    error_message = "prod debe tener 3 réplicas"
  }
}
