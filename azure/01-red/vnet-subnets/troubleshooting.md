# Azure · VNet y Subnets · Troubleshooting

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `NetcfgSubnetRangeOutsideVnet` al crear subnet | El CIDR de la subnet no está dentro del address space | `az network vnet show ... --query addressSpace` | Usar un rango contenido en la VNet o ampliar el address space |
| `NetcfgInvalidSubnet` / solapamiento | Dos subnets se solapan | Listar subnets con sus CIDR | Corregir el rango |
| "Subnet is full" / no se crean más nodos o instancias | Quedan 0 IP útiles (recuerda las 5 reservadas) | Portal: subnet → IP disponibles | Subnet más grande, otro modelo de red (overlay en AKS) |
| No se puede cambiar el address space | Hay peerings o recursos que dependen | Estado de los peerings | Sincronizar el peering tras el cambio o recrearlo |
| Servicio rechaza la subnet ("subnet not delegated") | Falta delegación | `az network vnet subnet show --query delegations` | Delegar al proveedor correcto o usar otra subnet |
| Servicio rechaza la subnet ("subnet must be empty") | Hay otros recursos en la subnet | Listar recursos conectados | Subnet dedicada |
| VM sin salida a internet | Sin NAT Gateway / IP pública, o salida implícita retirada | Effective routes de la NIC | Asociar NAT Gateway a la subnet |
| Nombre no resuelve dentro de la VNet | DNS personalizado mal configurado | Configuración DNS de la VNet | Volver a DNS de Azure o configurar el reenvío correcto |
| Conexiones que se cortan tras minutos inactivas | Idle timeout del balanceador/NAT | Revisar idle timeout | Mantener viva la conexión (keepalive) y acortar vida del pool |
| Cuota excedida al crear IP o VNet | Límite de la suscripción | `az network list-usages -l <región> -o table` | Pedir aumento de cuota |

## Comandos de diagnóstico útiles
```bash
az network vnet show -g <rg> -n <vnet> -o json
az network vnet subnet show -g <rg> --vnet-name <vnet> -n <subnet> -o json
az network nic show-effective-route-table -g <rg> -n <nic> -o table
az network nic list-effective-nsg -g <rg> --name <nic>
az network list-usages -l eastus2 -o table
```
