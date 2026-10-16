# Azure · Peering y Hub-and-Spoke · Troubleshooting

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| Peering en `Initiated` | Falta el recurso del otro sentido | Listar peerings de **ambas** VNets | Crear el peering faltante |
| Peering en `Disconnected` | Se eliminó un lado | Estado en ambos lados | Recrear el lado borrado |
| No se puede crear (rangos) | Address spaces solapados | Comparar rangos | Rediseñar rangos |
| A ve a B, B ve a C, A no ve a C | No transitivo | Topología | Hub con firewall o peering A↔C |
| Spoke no llega a on-premises | Falta gateway transit / use remote gateways, o rutas | Opciones del peering; rutas efectivas | Habilitar transit en hub y remote gateways en spoke |
| Funciona en un sentido | Opciones distintas en cada lado | Revisar flags de los dos peerings | Igualar `allow_virtual_network_access` |
| Timeouts spoke→spoke con firewall | Ruteo asimétrico o regla de firewall faltante | `show-next-hop`; logs del firewall | UDR en ambos lados; abrir la regla |
| No resuelve nombres privados desde el spoke | Zona privada sin enlace al spoke | Enlaces de la zona | Enlazar el spoke |
| "Remote virtual network address space changed" | Se cambió el address space | Estado `FullSyncPending` | Sincronizar el peering |
| Costo de red inesperado | Tráfico entre regiones | Cost Management por tipo de tráfico | Acercar servicios o cachear |
| Permiso denegado al crear peering | Falta permiso en la VNet remota | Mensaje de error | Rol en el otro lado |

## Comandos
```bash
az network vnet peering list -g <rg> --vnet-name <vnet> -o table
az network vnet peering show -g <rg> --vnet-name <vnet> -n <peering> -o json
az network vnet peering sync -g <rg> --vnet-name <vnet> -n <peering>
az network watcher show-next-hop -g <rg> --vm <vm> --source-ip <ip> --dest-ip <ip>
```
