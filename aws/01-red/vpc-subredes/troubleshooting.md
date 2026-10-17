# AWS · Red · VPC y subredes · Troubleshooting

Orden: **¿la subred tiene ruta? → ¿la ruta apunta al salto correcto? → ¿hay IP disponible? → ¿DNS de la VPC activo? → Flow Logs.**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| Instancia en «subred pública» sin internet | Sin IP pública, sin ruta al IGW o SG/NACL | Tabla de rutas asociada; `describe-instances` | Ruta `0.0.0.0/0 → igw`; IP pública/elástica; revisar SG y NACL |
| Privados sin salida a internet | Sin ruta al NAT o NAT en subred equivocada | Rutas de la subred privada | `0.0.0.0/0 → nat-xxxx`; el NAT debe estar en una subred **pública** |
| `InsufficientFreeAddressesInSubnet` | Subred sin IP libres | `AvailableIpAddressCount` | Subred nueva más grande o bloque secundario |
| `CidrConflict` / no se puede crear peering o TGW | Solapamiento | CIDR de ambas VPC | Rediseñar o usar PrivateLink |
| El nombre DNS no resuelve en la VPC | `enableDnsSupport`/`enableDnsHostnames` apagados | Atributos de la VPC | Activarlos |
| Un NAT se «satura» (conexiones perdidas) | Puertos de origen agotados | Métrica `ErrorPortAllocation` | Más NAT (por AZ/subred), reutilizar conexiones, endpoints |
| Tráfico entre AZ muy caro | Llamadas cruzadas | Flow Logs por subred/AZ | Afinidad de zona, un NAT por AZ |
| Ruta a un peering que no funciona | Falta la ruta en **uno** de los lados | Ambas tablas | Añadir la ruta en las dos VPC |
| Flow Logs vacíos | Destino sin permisos o filtro | Estado del Flow Log | Política del bucket/rol; filtro `ALL` |
| `terraform destroy` falla borrando la VPC | Dependencias (ENI, endpoints) | Interfaces de red en la VPC | Eliminar primero ENI, endpoints y balanceadores |
