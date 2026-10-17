# Prueba sin credenciales: las reglas del mapa de cuentas se comprueban en el plan.
mock_provider "aws" {
  mock_data "aws_organizations_organization" {
    defaults = {
      roots = [{ id = "r-ab12", arn = "arn:aws:organizations::111122223333:root/o-x/r-ab12", name = "Root", policy_types = [] }]
    }
  }
  mock_resource "aws_organizations_organizational_unit" {
    defaults = {
      id = "ou-ab12-abcd1234"
    }
  }
  mock_resource "aws_organizations_account" {
    defaults = {
      id = "111122223333"
    }
  }
  mock_resource "aws_organizations_policy" {
    defaults = {
      id = "p-abcd1234"
    }
  }
  mock_data "aws_iam_policy_document" {
    defaults = {
      json = "{\"Version\":\"2012-10-17\",\"Statement\":[]}"
    }
  }
}

variables {
  bucket_logs = "modalima-logs-archivo-444455556666"
  cuentas = {
    "pagos-prod" = {
      correo              = "aws+pagos-prod@modalima.example"
      ou                  = "prod"
      equipo              = "pagos"
      centro_de_costos    = "CC-2210"
      presupuesto_mensual = 1800
      cidr                = "10.20.0.0/20"
    }
  }
}

run "cuenta_valida_se_planifica" {
  command = plan
  assert {
    condition     = length(aws_organizations_account.carga) == 1 && length(aws_budgets_budget.cuenta) == 1
    error_message = "Debe planificar una cuenta y su presupuesto."
  }
}

run "nombre_invalido_se_rechaza" {
  command = plan
  variables {
    cuentas = {
      "Pagos_Prod" = {
        correo              = "aws+pagos-prod@modalima.example"
        ou                  = "prod"
        equipo              = "pagos"
        centro_de_costos    = "CC-2210"
        presupuesto_mensual = 1800
        cidr                = "10.20.0.0/20"
      }
    }
  }
  expect_failures = [var.cuentas]
}

run "prod_fuera_de_la_ou_prod_se_rechaza" {
  command = plan
  variables {
    cuentas = {
      "pagos-prod" = {
        correo              = "aws+pagos-prod@modalima.example"
        ou                  = "noprod"
        equipo              = "pagos"
        centro_de_costos    = "CC-2210"
        presupuesto_mensual = 1800
        cidr                = "10.20.0.0/20"
      }
    }
  }
  expect_failures = [var.cuentas]
}

run "cidr_repetido_se_rechaza" {
  command = plan
  variables {
    cuentas = {
      "pagos-prod" = {
        correo              = "aws+pagos-prod@modalima.example"
        ou                  = "prod"
        equipo              = "pagos"
        centro_de_costos    = "CC-2210"
        presupuesto_mensual = 1800
        cidr                = "10.20.0.0/20"
      }
      "pagos-dev" = {
        correo              = "aws+pagos-dev@modalima.example"
        ou                  = "noprod"
        equipo              = "pagos"
        centro_de_costos    = "CC-2210"
        presupuesto_mensual = 300
        cidr                = "10.20.0.0/20"
      }
    }
  }
  expect_failures = [var.cuentas]
}
