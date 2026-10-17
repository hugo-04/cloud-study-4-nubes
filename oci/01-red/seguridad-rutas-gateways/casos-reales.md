# Oracle OCI · Red · Listas de seguridad, NSG, rutas y gateways · Casos reales

## 1. El SSH abierto al mundo
**Qué pasó:** intentos de acceso masivos al puerto 22 de una VM de pruebas.
**Causa:** una regla `0.0.0.0/0 → 22` «temporal» que quedó semanas.
**Arreglo:** acceso por el servicio Bastion y auditoría diaria de reglas.
**Lección:** lo temporal se olvida; automatiza la revisión.

## 2. Funcionaba en dev, no en prod
**Qué pasó:** la app no llegaba a la base de datos solo en producción.
**Causa:** en dev la regla era por CIDR amplio; en prod, por NSG, y a los nodos nuevos les faltaba el NSG de la app.
**Arreglo:** el NSG se asigna por Terraform al grupo de nodos.
**Lección:** las reglas por NSG son precisas, pero exigen que el NSG esté asignado.

## 3. La regla sin estado a medias
**Qué pasó:** conexiones que se quedaban colgadas hacia un servicio.
**Causa:** regla de entrada sin estado sin su regla de salida de respuesta.
**Arreglo:** pasar a con estado.
**Lección:** sin estado = dos reglas.

## 4. La ruta más específica
**Qué pasó:** el tráfico hacia on-premises salía por Internet.
**Causa:** existía `0.0.0.0/0` hacia el NAT pero faltaba la ruta `192.168.0.0/16` hacia la DRG.
**Arreglo:** añadir la ruta específica.
**Lección:** gana el prefijo más largo; revisa las dos tablas.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Intentos en el puerto 22 | Regla abierta olvidada | Bastion + auditoría |
| 2 | Solo falla en prod | NSG sin asignar | Terraform |
| 3 | Conexiones colgadas | Regla sin estado | Con estado |
| 4 | Sale por Internet | Falta ruta específica | Ruta a la DRG |
