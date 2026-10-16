# Azure · Private Endpoint y DNS · Troubleshooting

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| El nombre resuelve a **IP pública** | La zona privada no está enlazada a la VNet que consulta | Zona → *Virtual network links* | Crear el enlace |
| El nombre **no resuelve** | DNS personalizado sin reenvío, o zona inexistente | DNS configurado en la VNet; `nslookup` | Reenviar a `168.63.129.16` o usar DNS Private Resolver |
| Resuelve a IP privada pero hay **timeout** | NSG/UDR en la subnet del PE o en el origen; PE no aprobado | `test-ip-flow`; estado de la conexión | Permitir el puerto; aprobar la conexión |
| Conexión del PE en `Pending` | El recurso es de otra suscripción/tenant | Estado de la conexión en el recurso destino | Aprobar desde el destino |
| Conexión en `Rejected`/`Disconnected` | El dueño la rechazó o se recreó el recurso | Estado | Recrear el PE |
| `403 This request is not authorized to perform this operation` en Storage | Acceso público cerrado y la petición viene de la red pública (DNS no usa el PE) | `nslookup` desde donde corre la app | Arreglar DNS; revisar red |
| `403` con red OK | Falta rol de datos (RBAC) | Roles asignados | Asignar Storage Blob Data Reader/Contributor |
| Error TLS (`certificate does not match`) | Se conecta por IP o por un nombre que no es el del servicio | Cómo se arma la URL | Conectar por el nombre original |
| Funciona en la VM, no desde on-premises | DNS de on-premises no conoce las zonas privadas | Reenviadores condicionales | DNS Private Resolver (inbound) |
| Funciona en una región, no en otra | VNet de la otra región sin enlace a la zona | Enlaces de la zona | Enlazar la VNet |
| Registro A faltante o incorrecto | El PE se recreó y quedó un registro viejo, o no hay zone group | Registros A de la zona | Crear zone group; borrar el registro obsoleto |
| El mismo servicio resuelve distinto en dos VNets | Zonas duplicadas o enlaces cruzados | Listar zonas con el mismo nombre | Una zona central |
| PE no se crea (error de subnet) | Políticas de red/permisos o subnet incorrecta | Mensaje de error; permisos | Subnet adecuada, rol correcto |

## Comandos
```bash
nslookup <nombre>                                  # desde DENTRO de la VNet
az network private-endpoint show -g <rg> -n <pe> -o json
az network private-dns zone list -o table
az network private-dns link vnet list -g <rg> -z <zona> -o table
az network private-dns record-set a list -g <rg> -z <zona> -o table
az storage account show -n <st> --query publicNetworkAccess
```
