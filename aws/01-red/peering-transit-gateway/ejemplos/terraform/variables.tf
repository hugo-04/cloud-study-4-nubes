variable "region" {
  type    = string
  default = "us-east-1"
}

variable "vpcs" {
  description = "VPC a conectar por Transit Gateway: id, CIDR, segmento, tabla(s) de rutas y subredes para el adjunto (una por AZ)."
  type = map(object({
    vpc_id           = string
    cidr             = string
    segmento         = string # prod | dev | compartida
    tablas_ruta_ids  = list(string)
    subredes_adjunto = list(string)
  }))
}

variable "vpc_a_id" {
  description = "VPC A del peering."
  type        = string
}

variable "vpc_b_id" {
  description = "VPC B del peering."
  type        = string
}

variable "cidr_vpc_a" {
  type = string
}

variable "cidr_vpc_b" {
  type = string
}

variable "tablas_ruta_a" {
  type = list(string)
}

variable "tablas_ruta_b" {
  type = list(string)
}

variable "cuentas_a_compartir" {
  description = "IDs de cuenta (o ARN de la organización) con los que se comparte el TGW por RAM."
  type        = list(string)
  default     = []
}
