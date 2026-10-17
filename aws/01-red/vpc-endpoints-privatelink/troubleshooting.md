# AWS · VPC Endpoints, PrivateLink y Route 53 · Troubleshooting

Orden: **¿resuelve a IP privada? → ¿el SG del endpoint permite 443 desde la app? → ¿la política de endpoint y de IAM lo permiten? → ¿hay endpoint en esa AZ? → ¿misma región?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| El nombre resuelve a IP **pública** | DNS privado apagado o VPC sin DNS | `nslookup sqs.us-east-1.amazonaws.com` desde la app | `private_dns_enabled = true`; `enableDnsHostnames` en la VPC |
| Timeout hacia el servicio | SG del endpoint no permite 443 | SG del endpoint | Regla 443 desde el SG de la app |
| `AccessDenied` solo por el endpoint | Política de endpoint demasiado estricta | Política del endpoint | Añadir la acción/recurso; recuerda que IAM también debe permitir |
| S3 no responde desde la VPC | Sin gateway o sin ruta en esa tabla | Tabla de rutas de la subred | Asociar el endpoint a **las tablas correctas** |
| `CannotPullContainerError` en Fargate sin NAT | Faltan `ecr.api`, `ecr.dkr`, S3 o `logs` | Endpoints existentes | Crear los que faltan |
| Funciona en la AZ A y falla en la B | Sin ENI del endpoint en B | Subredes del endpoint | Añadir subred de B |
| El endpoint queda `pendingAcceptance` | PrivateLink requiere aprobación | Consola del dueño del servicio | Aceptar la conexión |
| El bucket niega con `aws:SourceVpce` | Llamada por otro camino (NAT, otra VPC) | Origen real en CloudTrail | Usar el endpoint; ajustar la política |
| Un nombre interno no resuelve desde la red local | Falta el Resolver entrante o la reenvío | Endpoints de Resolver | Crear regla/endpoint |
| La zona privada no resuelve en una VPC | VPC sin asociar | Asociaciones de la zona | Asociar la VPC |
| Nombre cacheado con la IP antigua | Caché DNS de la JVM | `networkaddress.cache.ttl` | Bajar el TTL; reiniciar |
