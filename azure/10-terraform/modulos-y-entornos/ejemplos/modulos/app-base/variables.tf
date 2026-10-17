variable "nombre_aplicacion" {
  type        = string
  description = "Nombre corto de la aplicación (minúsculas y números, 3 a 14 caracteres)."

  validation {
    condition     = can(regex("^[a-z0-9]{3,14}$", var.nombre_aplicacion))
    error_message = "nombre_aplicacion debe tener 3 a 14 letras minúsculas o números."
  }
}

variable "entorno" {
  type        = string
  description = "Entorno de despliegue."

  validation {
    condition     = contains(["dev", "qa", "prod"], var.entorno)
    error_message = "entorno debe ser dev, qa o prod."
  }
}

variable "ubicacion" {
  type        = string
  description = "Región de Azure."
  default     = "eastus2"
}

variable "sufijo" {
  type        = string
  description = "Sufijo que vuelve único el nombre global de la cuenta (3 a 6 caracteres)."
  default     = "001"

  validation {
    condition     = can(regex("^[a-z0-9]{3,6}$", var.sufijo))
    error_message = "sufijo debe tener 3 a 6 letras minúsculas o números."
  }
}

variable "dueno" {
  type        = string
  description = "Equipo responsable (etiqueta obligatoria)."

  validation {
    condition     = length(trimspace(var.dueno)) > 0
    error_message = "dueno no puede estar vacío."
  }
}

variable "contenedores" {
  type        = set(string)
  description = "Contenedores de blobs a crear (privados)."
  default     = []
}

variable "ips_permitidas" {
  type        = list(string)
  description = "IP o rangos CIDR con acceso a la cuenta. Vacío = solo servicios de confianza de Azure."
  default     = []
}

variable "restringir_red" {
  type        = bool
  description = "true: firewall en Deny con las excepciones indicadas."
  default     = true
}

variable "replicacion" {
  type        = string
  description = "Tipo de replicación de la cuenta."
  default     = "ZRS"

  validation {
    condition     = contains(["LRS", "ZRS", "GRS", "GZRS"], var.replicacion)
    error_message = "replicacion debe ser LRS, ZRS, GRS o GZRS."
  }
}

variable "lectores" {
  type        = map(string)
  description = "Identidades con lectura de blobs: clave lógica (estable) => principal_id. Las claves deben conocerse al planificar."
  default     = {}
}

variable "etiquetas" {
  type        = map(string)
  description = "Etiquetas adicionales."
  default     = {}
}
