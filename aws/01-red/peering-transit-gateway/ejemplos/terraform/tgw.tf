locals {
  segmentos = toset([for v in values(var.vpcs) : v.segmento])

  # Qué segmentos puede ALCANZAR cada segmento (su tabla propaga a los demás)
  alcanzables = {
    prod       = ["compartida"]
    dev        = ["compartida"]
    compartida = ["prod", "dev", "compartida"]
  }
}

resource "aws_ec2_transit_gateway" "central" {
  description                     = "TGW central de ModaLima"
  amazon_side_asn                 = 64512
  auto_accept_shared_attachments  = "disable" # aceptación manual
  default_route_table_association = "disable" # control explícito
  default_route_table_propagation = "disable"
  dns_support                     = "enable"
  tags                            = { Name = "tgw-central" }
}

resource "aws_ec2_transit_gateway_route_table" "segmento" {
  for_each = local.segmentos

  transit_gateway_id = aws_ec2_transit_gateway.central.id
  tags               = { Name = "tgw-rt-${each.value}" }
}

resource "aws_ec2_transit_gateway_vpc_attachment" "vpc" {
  for_each = var.vpcs

  transit_gateway_id                              = aws_ec2_transit_gateway.central.id
  vpc_id                                          = each.value.vpc_id
  subnet_ids                                      = each.value.subredes_adjunto
  transit_gateway_default_route_table_association = false
  transit_gateway_default_route_table_propagation = false
  tags                                            = { Name = "tgw-att-${each.key}" }
}

# Asociación: cada adjunto usa la tabla de SU segmento para salir
resource "aws_ec2_transit_gateway_route_table_association" "vpc" {
  for_each = var.vpcs

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.vpc[each.key].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.segmento[each.value.segmento].id
}

# Propagación: las rutas de cada adjunto se publican en las tablas de los segmentos que pueden alcanzarlo
locals {
  propagaciones = flatten([
    for nombre, v in var.vpcs : [
      for origen, destinos in local.alcanzables : {
        clave   = "${nombre}-en-${origen}"
        vpc     = nombre
        tabla   = origen
        aplicar = contains(destinos, v.segmento)
      } if contains(local.segmentos, origen)
    ]
  ])
}

resource "aws_ec2_transit_gateway_route_table_propagation" "p" {
  for_each = { for p in local.propagaciones : p.clave => p if p.aplicar }

  transit_gateway_attachment_id  = aws_ec2_transit_gateway_vpc_attachment.vpc[each.value.vpc].id
  transit_gateway_route_table_id = aws_ec2_transit_gateway_route_table.segmento[each.value.tabla].id
}

# Rutas en las VPC hacia las redes de OTROS segmentos (prefijo específico, no 0.0.0.0/0)
resource "aws_route" "vpc_hacia_tgw" {
  for_each = {
    for par in flatten([
      for nombre, v in var.vpcs : [
        for t in v.tablas_ruta_ids : { clave = "${nombre}-${t}", tabla = t, vpc = nombre }
      ]
    ]) : par.clave => par
  }

  route_table_id         = each.value.tabla
  destination_cidr_block = "10.0.0.0/8"
  transit_gateway_id     = aws_ec2_transit_gateway.central.id

  depends_on = [aws_ec2_transit_gateway_vpc_attachment.vpc]
}

# Compartir el TGW con otras cuentas (AWS RAM)
resource "aws_ram_resource_share" "tgw" {
  count = length(var.cuentas_a_compartir) == 0 ? 0 : 1

  name                      = "tgw-central"
  allow_external_principals = false
}

resource "aws_ram_resource_association" "tgw" {
  count = length(var.cuentas_a_compartir) == 0 ? 0 : 1

  resource_arn       = aws_ec2_transit_gateway.central.arn
  resource_share_arn = aws_ram_resource_share.tgw[0].arn
}

resource "aws_ram_principal_association" "cuentas" {
  for_each = toset(var.cuentas_a_compartir)

  principal          = each.value
  resource_share_arn = aws_ram_resource_share.tgw[0].arn
}

output "tgw_id" {
  value = aws_ec2_transit_gateway.central.id
}
