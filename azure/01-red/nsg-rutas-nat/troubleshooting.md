# Azure · NSG, Rutas y NAT · Troubleshooting

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| Timeout hacia un puerto que "debería estar abierto" | Un NSG (subnet o NIC) lo niega, o falta Allow | `az network watcher test-ip-flow` → muestra la regla que decide | Corregir prioridad/regla; recuerda que subnet y NIC se suman |
| "Todos se ven con todos" en la VNet | Falta Deny de `VirtualNetwork` | NSG efectivo de la NIC | Regla Deny de prioridad < 65000 |
| Mi regla Deny no hace efecto | Otra regla Allow con menor número coincide antes | Ordenar reglas por prioridad | Reordenar o ajustar |
| No se puede borrar el NSG | Está asociado a subnet o NIC | `az network nsg show --query "{s:subnets,n:networkInterfaces}"` | Desasociar primero |
| Salida a internet cortada tras poner UDR `0.0.0.0/0` | El next hop no existe, no tiene IP forwarding o no permite el tráfico | `show-next-hop`, rutas efectivas | Verificar firewall/NVA y su reenvío |
| Ida funciona y vuelta no | Ruteo asimétrico | Comparar rutas de las dos subnets | Misma Route Table en ambos lados |
| Conexiones fallan solo en picos | Agotamiento de SNAT | Métricas de SNAT de LB/NAT Gateway | NAT Gateway, más IP, pool de conexiones |
| Un tercero rechaza nuestra IP | La IP de salida cambió | IP pública de salida | NAT Gateway con IP estática |
| NSG flow logs ya no aparecen | Función en retiro | Estado del servicio | Migrar a VNet flow logs |
| Rutas "None" bloquean tráfico propio | Rutas de sistema por rangos no usados | Rutas efectivas | Agregar la ruta o rango correcto |
| Cambios de NSG no parecen aplicarse | Se editó otro NSG o una asociación distinta | `list-effective-nsg` de la NIC real | Editar el NSG correcto |

## Comandos útiles
```bash
az network watcher test-ip-flow -g <rg> --vm <vm> --direction Inbound --protocol TCP --local <ip>:<puerto> --remote <ip>:<puerto>
az network watcher show-next-hop -g <rg> --vm <vm> --source-ip <ip> --dest-ip <ip>
az network nic list-effective-nsg -g <rg> --name <nic>
az network nic show-effective-route-table -g <rg> -n <nic> -o table
az network nsg rule list -g <rg> --nsg-name <nsg> --include-default -o table
```
