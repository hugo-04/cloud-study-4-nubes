# Prueba de contrato: el archivo que genera el portal (Java) debe ser aceptado por el módulo real.
#   tofu -chdir=envs/dev test        (usa servicios.auto.tfvars.json de la carpeta)
mock_provider "aws" {}

run "el_archivo_generado_es_aceptado" {
  command = plan

  assert {
    condition     = length(module.servicio) >= 1
    error_message = "El archivo debe definir al menos un servicio."
  }

  assert {
    condition     = alltrue([for k, m in module.servicio : startswith(m.grupo_logs, "/app/dev-${k}")])
    error_message = "Los nombres no siguen la convención /app/<entorno>-<servicio>."
  }
}
