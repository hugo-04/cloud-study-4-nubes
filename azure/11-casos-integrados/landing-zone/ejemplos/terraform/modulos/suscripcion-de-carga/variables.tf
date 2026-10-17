variable "equipo" {
  description = "Nombre corto del equipo (minúsculas, 3-12 caracteres)."
  type        = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,11}$", var.equipo))
    error_message = "equipo: minúsculas y dígitos, 3-12 caracteres, empieza con letra."
  }
}

variable "entorno" {
  type = string
  validation {
    condition     = contains(["dev", "prod"], var.entorno)
    error_message = "entorno debe ser dev o prod."
  }
}

variable "ubicacion" {
  type    = string
  default = "eastus2"
}

variable "subscription_id" {
  description = "Suscripción ya creada por el proceso de facturación de la empresa."
  type        = string
}

variable "grupo_de_administracion_id" {
  description = "ID completo del grupo de administración destino (landing zone Corp u Online)."
  type        = string
}

variable "grupo_del_equipo" {
  description = "Object ID del grupo de Entra ID del equipo (nunca personas sueltas)."
  type        = string
}

variable "propietario" {
  description = "Correo del responsable (etiqueta owner)."
  type        = string
}

variable "centro_de_costo" {
  type = string
}

variable "presupuesto_mensual" {
  type = number
  validation {
    condition     = var.presupuesto_mensual >= 100 && var.presupuesto_mensual <= 100000
    error_message = "presupuesto_mensual entre 100 y 100000."
  }
}

variable "correos_de_alerta" {
  type = list(string)
  validation {
    condition     = length(var.correos_de_alerta) >= 1
    error_message = "Debe haber al menos un correo de alerta."
  }
}

variable "cidr_red" {
  description = "Bloque asignado por el servicio de direcciones (ver el asignador en Java). No lo inventes a mano."
  type        = string
  validation {
    condition     = can(cidrnetmask(var.cidr_red))
    error_message = "cidr_red debe ser un CIDR válido."
  }
}

variable "red_hub_id" {
  description = "ID de la VNet hub (suscripción de conectividad)."
  type        = string
}

variable "red_hub_nombre" {
  type = string
}

variable "red_hub_grupo_de_recursos" {
  type = string
}

variable "workspace_central_id" {
  description = "ID del espacio de trabajo de Log Analytics central (suscripción de gestión)."
  type        = string
}
