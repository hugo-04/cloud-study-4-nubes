# AWS · Peering y Transit Gateway · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. La malla de once peerings
**Qué pasó:** seis VPC conectadas con peerings uno a uno; cada VPC nueva exigía cinco peerings y rutas en doce tablas. **Solución:** Transit Gateway con tablas por segmento. **Lección:** el peering no escala por encima de unas pocas VPC.

## 2. «A ve a C a través de B»
**Qué pasó:** Pedidos alcanzaba a Catálogo y Catálogo a Inventario; el equipo esperaba que Pedidos llegara a Inventario. **Causa:** el peering no es transitivo. **Solución:** TGW o un peering directo. **Lección:** pregunta «¿transitivo?» antes de dibujar flechas.

## 3. Rutas solo de un lado
**Qué pasó:** peering «activo» y aun así hay timeout. **Causa:** la ruta existía en la VPC A pero no en B. **Solución:** ruta en ambas y en las tablas correctas. **Lección:** peering son dos rutas y dos aceptaciones.

## 4. Prod hablaba con dev
**Qué pasó:** una prueba en dev llegó a una base de producción. **Causa:** una sola tabla de rutas del TGW donde todos propagaban. **Solución:** tablas `prod`, `dev` y `compartida`, y asociaciones separadas. **Lección:** la segmentación es la razón de ser del TGW.

## 5. La factura por GB
**Qué pasó:** dos VPC con 200 TB/mes de tráfico por TGW. **Solución:** peering directo entre las dos (sin cargo por GB de la conexión; solo transferencia entre AZ). **Lección:** compara el costo por GB antes de centralizar.

## 6. Mismo CIDR, siete cuentas
**Qué pasó:** una adquisición trajo redes con `10.0.0.0/16`. **Solución:** PrivateLink para exponer las pocas APIs necesarias; plan de renumeración a largo plazo. **Lección:** PrivateLink es la salida cuando los CIDR chocan.

| Problema | Solución |
|---|---|
| Malla de peerings | TGW |
| Transitividad | TGW / peering directo |
| Rutas a medias | Ambos lados |
| Prod↔dev | Tablas por segmento |
| Costo por GB | Peering para pares de alto tráfico |
| CIDR solapados | PrivateLink |
