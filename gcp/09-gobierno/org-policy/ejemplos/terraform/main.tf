terraform {
  required_version = ">= 1.5"
  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 8.0"
    }
  }
}

variable "organizacion" {
  type = string
}

variable "carpeta_prod" {
  type        = string
  description = "folders/<id>"
}

variable "cliente_identity" {
  type        = string
  description = "ID de cliente de Cloud Identity (C0xxxx)"
}

locals {
  org       = "organizations/${var.organizacion}"
  booleanas = ["sql.restrictPublicIp", "iam.disableServiceAccountKeyCreation", "storage.publicAccessPrevention", "compute.requireOsLogin"]
}

resource "google_org_policy_policy" "booleanas" {
  for_each = toset(local.booleanas)
  name     = "${local.org}/policies/${each.value}"
  parent   = local.org

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}

resource "google_org_policy_policy" "sin_ip_externa" {
  name   = "${local.org}/policies/compute.vmExternalIpAccess"
  parent = local.org

  spec {
    rules {
      deny_all = "TRUE"
    }
  }
}

resource "google_org_policy_policy" "dominios" {
  name   = "${local.org}/policies/iam.allowedPolicyMemberDomains"
  parent = local.org

  spec {
    rules {
      values {
        allowed_values = [var.cliente_identity]
      }
    }
  }
}

resource "google_org_policy_policy" "ubicaciones_prod" {
  name   = "${var.carpeta_prod}/policies/gcp.resourceLocations"
  parent = var.carpeta_prod

  spec {
    rules {
      values {
        allowed_values = ["in:southamerica-locations"]
      }
    }
  }

  # Probar primero sin bloquear
  dry_run_spec {
    rules {
      values {
        allowed_values = ["in:southamerica-west1-locations"]
      }
    }
  }
}

resource "google_org_policy_custom_constraint" "gke_privado" {
  name           = "custom.gkeNodosPrivados"
  parent         = local.org
  display_name   = "GKE solo con nodos privados"
  action_type    = "DENY"
  condition      = "resource.privateClusterConfig.enablePrivateNodes == false"
  method_types   = ["CREATE", "UPDATE"]
  resource_types = ["container.googleapis.com/Cluster"]
}

resource "google_org_policy_policy" "gke_privado" {
  name   = "${local.org}/policies/${google_org_policy_custom_constraint.gke_privado.name}"
  parent = local.org

  spec {
    rules {
      enforce = "TRUE"
    }
  }
}
