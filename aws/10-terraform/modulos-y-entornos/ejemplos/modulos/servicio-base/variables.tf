variable "nombre" {
  description = "Nombre del servicio (minúsculas, números y guiones; 3 a 30 caracteres)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}[a-z0-9]$", var.nombre))
    error_message = "El nombre debe tener 3 a 30 caracteres: minúsculas, números y guiones, empezando por letra y sin terminar en guion."
  }
}

variable "entorno" {
  description = "Entorno de despliegue"
  type        = string

  validation {
    condition     = contains(["dev", "stg", "prod"], var.entorno)
    error_message = "El entorno debe ser dev, stg o prod."
  }
}

variable "dueno" {
  description = "Correo del equipo responsable"
  type        = string

  validation {
    condition     = can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", var.dueno))
    error_message = "El dueño debe ser un correo válido."
  }
}

variable "equipo" {
  description = "Equipo al que se le asigna el costo (etiqueta equipo)"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,28}$", var.equipo))
    error_message = "El equipo debe estar en minúsculas, números y guiones."
  }
}

variable "retencion_logs_dias" {
  description = "Días de retención del grupo de logs (valores que admite CloudWatch Logs)"
  type        = number
  default     = 30

  validation {
    condition     = contains([1, 3, 5, 7, 14, 30, 60, 90, 120, 150, 180, 365, 400, 545, 731, 1096, 1827, 2192, 2557, 2922, 3288, 3653], var.retencion_logs_dias)
    error_message = "La retención debe ser uno de los valores que admite CloudWatch Logs (por ejemplo 7, 14, 30, 90, 365)."
  }
}

variable "max_receives" {
  description = "Intentos de lectura antes de enviar el mensaje a la cola de fallos"
  type        = number
  default     = 5

  validation {
    condition     = var.max_receives >= 1 && var.max_receives <= 1000 && floor(var.max_receives) == var.max_receives
    error_message = "max_receives debe ser un entero entre 1 y 1000."
  }
}

variable "retencion_mensajes_dias" {
  description = "Días que se conservan los mensajes de la cola principal"
  type        = number
  default     = 4

  validation {
    condition     = var.retencion_mensajes_dias >= 1 && var.retencion_mensajes_dias <= 14 && floor(var.retencion_mensajes_dias) == var.retencion_mensajes_dias
    error_message = "La retención de mensajes debe ser un entero entre 1 y 14 días."
  }
}

variable "arn_limite_permisos" {
  description = "ARN de la política usada como límite de permisos del rol (obligatoria en prod)"
  type        = string
  default     = null
}

variable "etiquetas_extra" {
  description = "Etiquetas adicionales (no pueden pisar las obligatorias)"
  type        = map(string)
  default     = {}
}
