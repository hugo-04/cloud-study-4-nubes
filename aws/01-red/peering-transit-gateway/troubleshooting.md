# AWS · Peering y Transit Gateway · Troubleshooting

Orden: **¿hay solapes? → ¿conexión/adjunto en estado `available`/`active`? → ¿rutas en AMBAS VPC? → ¿asociación y propagación en el TGW? → SG y NACL → Reachability Analyzer.**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| Peering en `pending-acceptance` | Falta aceptar | `describe-vpc-peering-connections` | Aceptar desde la cuenta del par |
| Peering activo pero timeout | Falta la ruta en una de las dos tablas | Tablas de ambas VPC | Rutas en ambos lados |
| No se puede crear el peering | CIDR solapados | CIDR de las dos | Rediseñar o PrivateLink |
| A→C por B no funciona | Peering no transitivo | — | TGW o peering directo |
| Adjunto de TGW en `pending-acceptance` | Aceptación manual | Estado del adjunto | Aceptar |
| El TGW está pero no hay tráfico | Sin rutas hacia el TGW en la VPC | Tabla de rutas de la VPC | `10.0.0.0/8 → tgw` |
| Hay ruta en la VPC y no llega | Sin asociación/propagación en el TGW | Tablas del TGW | Asociar el adjunto y propagar |
| Prod alcanza dev | Propagación a la tabla equivocada | Propagaciones | Separar tablas |
| Tráfico con inspección falla de vuelta | AZ asimétrica | Appliance mode | Activarlo en el adjunto de inspección |
| `blackhole` en una ruta | Adjunto eliminado | Rutas del TGW | Limpiar o restaurar |
| Peering entre regiones sin SG por referencia | No se admite entre regiones | — | Usa CIDR |
| Nombres privados no resuelven entre VPC | Resolución DNS del peering apagada | Opciones del peering | Activarla en ambos lados |
