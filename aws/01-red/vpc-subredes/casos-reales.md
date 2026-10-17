# AWS · Red · VPC y subredes · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. El clúster que se quedó sin IP
**Qué pasó:** EKS dejó de crear pods en una campaña. **Causa:** subredes `/26` de aplicación (59 IP) y cada pod consumía una IP de la VPC. **Solución:** subredes `/22` por AZ y un monitor de IP libres. **Lección:** en contenedores, las IP se agotan antes que la CPU.

## 2. Dos VPC, el mismo bloque
**Qué pasó:** al conectar la VPC de Pedidos con la de Catálogo, no había forma de enrutar. **Causa:** ambas usaban `10.0.0.0/16`. **Solución:** rediseño con un registro central de bloques. **Lección:** planifica los CIDR como las direcciones de una ciudad.

## 3. Un NAT para tres zonas
**Qué pasó:** cayó una AZ y todas las tareas dejaron de salir a internet. **Causa:** un único NAT en la AZ afectada. **Solución:** un NAT por AZ y una tabla de rutas privada por AZ. **Lección:** la alta disponibilidad se rompe en el eslabón más débil.

## 4. La factura del NAT
**Qué pasó:** 4 000 USD al mes de NAT. **Causa:** los servicios descargaban imágenes y subían a S3 por el NAT. **Solución:** endpoint de puerta de enlace de S3 (gratis) y endpoints de interfaz para ECR/Logs. **Lección:** mira el costo por GB procesado.

## 5. La base «privada» que no lo era
**Qué pasó:** una subred de datos tenía ruta al IGW por error y la base una IP pública. **Solución:** tablas de rutas por nivel, política que niega IP pública y consulta periódica. **Lección:** la privacidad se verifica, no se supone.

## 6. Sin Flow Logs cuando hacían falta
**Qué pasó:** un timeout intermitente sin datos para diagnosticar. **Solución:** Flow Logs en todas las VPC hacia una cuenta de registros. **Lección:** activar el registro después del incidente es tarde.

| Problema | Solución |
|---|---|
| IP agotadas | `/22` + monitor |
| CIDR duplicados | Registro central |
| NAT único | NAT por AZ |
| Costo de NAT | Endpoints |
| Datos expuestos | Rutas por nivel + política |
| Sin evidencia | Flow Logs |
