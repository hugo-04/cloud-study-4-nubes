# AWS · VPC Endpoints, PrivateLink y Route 53 · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. De 4 000 a 600 USD de NAT
**Qué pasó:** las tareas bajaban imágenes de ECR y subían a S3 por el NAT. **Solución:** gateway de S3 (gratis) e interfaz para `ecr.api`, `ecr.dkr`, `logs`. **Lección:** el NAT cobra por GB; los endpoints no cobran ese tráfico igual.

## 2. Fargate sin NAT que no arrancaba
**Qué pasó:** las tareas se quedaban en `PROVISIONING` y fallaban con «CannotPullContainerError». **Causa:** faltaba el endpoint de **S3** (las capas de ECR salen de S3) y el de `logs`. **Solución:** completar la lista. **Lección:** ECR necesita tres piezas, no una.

## 3. El DNS privado apagado
**Qué pasó:** el endpoint de SQS existía, pero el tráfico seguía saliendo por el NAT. **Causa:** `private_dns_enabled = false`; el nombre resolvía a la IP pública. **Solución:** activarlo y reiniciar los clientes (caché DNS). **Lección:** verifica la IP que resuelve, no solo que el endpoint exista.

## 4. Un servicio, ocho consumidores
**Qué pasó:** el equipo de Pagos necesitaba exponer una API a siete cuentas con CIDR solapados. **Solución:** NLB + endpoint service con aprobación manual. **Lección:** PrivateLink resuelve lo que el peering no puede (solapes y exposición mínima).

## 5. Un bucket «privado» que se leyó desde casa
**Qué pasó:** alguien con credenciales válidas descargó datos desde su portátil. **Solución:** política de bucket que niega todo si no viene de `aws:SourceVpce`. **Lección:** el endpoint también es una condición de seguridad.

## 6. Solo una AZ
**Qué pasó:** cuando falló la zona A, las apps de B y C perdieron SQS. **Causa:** el endpoint estaba solo en A. **Solución:** una ENI por AZ. **Lección:** la alta disponibilidad se aplica también a la red.

| Problema | Solución |
|---|---|
| Factura de NAT | Gateway + interfaces |
| Fargate sin arrancar | ECR + S3 + logs |
| DNS público | DNS privado |
| Exponer un servicio | PrivateLink |
| Datos fuera de la red | `aws:SourceVpce` |
| Fallo de zona | Endpoint en cada AZ |
