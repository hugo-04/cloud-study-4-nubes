# Entorno prod (en el repo real: entornos/prod/main.tf con su backend.tf)
terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }
}

provider "google" {
  project = "modalima-tienda-prod"
  region  = "southamerica-west1"
}

module "pedidos" {
  # En el repo real: source = "git::https://git.modalima.example/plataforma/modulos.git//microservicio?ref=v1.4.0"
  source = "../modulos/microservicio"

  nombre         = "pedidos"
  imagen         = "southamerica-west1-docker.pkg.dev/modalima-artefactos/apps/pedidos@sha256:0000000000000000000000000000000000000000000000000000000000000000"
  entorno        = "prod"
  equipo         = "tienda"
  min_instancias = 2
  max_instancias = 50
  secretos       = { PASARELA_TOKEN = "pasarela-token" }
  invocadores    = ["serviceAccount:gateway@modalima-tienda-prod.iam.gserviceaccount.com"]
}

output "url_pedidos" {
  value = module.pedidos.url
}
