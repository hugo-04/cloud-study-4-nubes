# Google Cloud · Red · VPC y subredes · Casos reales

## 1. La red automática que no se podía conectar
**Qué pasó:** ModaLima no pudo emparejar dos VPC creadas en modo automático.
**Causa:** ambas usaban los mismos rangos fijos.
**Arreglo:** VPC personalizadas con plan de direcciones.
**Lección:** el modo automático es para pruebas.

## 2. GKE sin IPs para pods
**Qué pasó:** el clúster dejó de crear pods en el Cyber.
**Causa:** rango secundario de pods demasiado pequeño.
**Arreglo:** nuevo rango secundario y node pool que lo usa; plan con margen.
**Lección:** dimensiona pods × nodos × crecimiento.

## 3. La VM que no llegaba a Cloud Storage
**Qué pasó:** un proceso por lotes sin IP externa fallaba al subir a un bucket.
**Causa:** la subred no tenía Private Google Access.
**Arreglo:** activar PGA.
**Lección:** sin IP pública, PGA o NAT.

## 4. Todos administraban la red
**Qué pasó:** un equipo de Café Andino borró una regla de firewall de otro.
**Causa:** cada proyecto tenía su VPC con permisos amplios.
**Arreglo:** Shared VPC con red administrada por plataforma y `networkUser` por subred.
**Lección:** centraliza la red, delega su uso.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | No se puede emparejar | Rangos automáticos | Modo personalizado |
| 2 | Pods pendientes | Secundario chico | Dimensionar |
| 3 | Sin acceso a APIs | Sin PGA | Activar PGA |
| 4 | Cambios cruzados | Redes por proyecto | Shared VPC |
