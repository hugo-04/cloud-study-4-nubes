# Azure · Diagnóstico de conectividad · Tabla maestra de síntomas

| Síntoma | Escalón | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|---|
| `UnknownHostException` | DNS | Zona privada inexistente o DNS propio sin reenvío | `nslookup`; DNS configurado de la VNet | Crear zona/enlace; reenviar a `168.63.129.16` |
| Resuelve a IP pública | DNS | Zona sin enlace a la VNet que consulta | Enlaces de la zona | Crear el enlace |
| Resuelve a IP privada, timeout | Ruta/Firewall | NSG, UDR, firewall central, PE no aprobado | `test-ip-flow`, `show-next-hop`, estado del PE | Permitir puerto, corregir rutas, aprobar PE |
| `Connection refused` | Puerto | Nada escucha, o servicio apagado | `nc -zv`; estado del servicio | Revisar servicio y puerto |
| Timeout solo en picos | Capacidad | Agotamiento SNAT, límites del destino | Métricas SNAT; cuotas | NAT Gateway, pool de conexiones |
| Error de certificado | TLS | Se usa IP o nombre equivocado; certificado vencido; CA no confiable | `openssl s_client` | Conectar por el nombre correcto; renovar |
| 401 | Identidad | Token ausente/caducado | Cabeceras y logs | Renovar token; revisar `audience` |
| 403 | Identidad (o firewall del servicio) | Falta rol, o el firewall del servicio niega por red | Roles asignados; reglas de red del servicio | Asignar rol; permitir la red o usar PE |
| 404 | Aplicación | Ruta equivocada | Logs de la app/gateway | Corregir URL |
| 5xx | Aplicación o backend | Error interno o backend caído | Logs, trazas | Corregir app/backend |
| Intermitente | Capacidad / DNS cache | SNAT, DNS TTL, instancia mala | Métricas; reproducir | Depende de la causa |
| "Funcionaba ayer" | Cambio | Despliegue, política, rotación | **Activity Log** | Revertir el cambio |

Desde el síntoma, salta a la carpeta del servicio:
- Red: [VNet](../vnet-subnets/troubleshooting.md) · [NSG/rutas/NAT](../nsg-rutas-nat/troubleshooting.md) · [Private Endpoint/DNS](../private-endpoint-dns/troubleshooting.md) · [Peering](../peering-hub-spoke/troubleshooting.md)
- Cómputo y API: [AKS](../../04-compute/aks/troubleshooting.md) · [APIM](../../05-ingress-api/apim/troubleshooting.md)
