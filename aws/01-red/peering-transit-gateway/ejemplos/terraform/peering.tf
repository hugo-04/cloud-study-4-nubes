# Peering entre dos VPC de la MISMA cuenta y región (cross-account: usar peer_owner_id y un aceptador con otro proveedor)
resource "aws_vpc_peering_connection" "a_b" {
  vpc_id      = var.vpc_a_id
  peer_vpc_id = var.vpc_b_id
  auto_accept = true # solo válido en la misma cuenta y región

  accepter {
    allow_remote_vpc_dns_resolution = true
  }

  requester {
    allow_remote_vpc_dns_resolution = true
  }

  tags = { Name = "pcx-a-b" }
}

# Rutas en AMBOS lados (si falta una, no hay tráfico)
resource "aws_route" "a_hacia_b" {
  for_each = toset(var.tablas_ruta_a)

  route_table_id            = each.value
  destination_cidr_block    = var.cidr_vpc_b
  vpc_peering_connection_id = aws_vpc_peering_connection.a_b.id
}

resource "aws_route" "b_hacia_a" {
  for_each = toset(var.tablas_ruta_b)

  route_table_id            = each.value
  destination_cidr_block    = var.cidr_vpc_a
  vpc_peering_connection_id = aws_vpc_peering_connection.a_b.id
}
