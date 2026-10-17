# AWS · SG, NACL, rutas y NAT · Troubleshooting

Orden de revisión (el camino completo): **ruta del origen → NACL de la subred de origen (salida) → SG de origen (salida) → NACL del destino (entrada y retorno) → SG del destino (entrada) → servicio escuchando**. Para verlo sin adivinar: [Reachability Analyzer y Flow Logs](../diagnostico-conectividad/README.md).

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| Timeout al conectar (se queda esperando) | SG o NACL descartan sin responder | Flow Logs: `REJECT`; Reachability Analyzer | Regla de entrada en el SG destino / NACL |
| `Connection refused` (rápido) | El tráfico llegó, nadie escucha en ese puerto | `ss -ltnp` en el destino | Levantar el servicio o corregir el puerto |
| Funciona A→B pero no B→A | SG con estado: la entrada de A no autoriza conexiones iniciadas por B | SG de A | Regla de entrada en A para B |
| Entra pero la respuesta no vuelve | NACL sin puertos efímeros | NACL de ambas subredes | Permitir `1024–65535` de retorno |
| Los privados no salen a internet | Sin ruta al NAT o NAT sin EIP / en subred privada | Tabla de rutas y estado del NAT | Ruta `0.0.0.0/0 → nat`; NAT en subred pública |
| Salen pero intermitente | Puertos de NAT agotados | Métrica `ErrorPortAllocation` | Pool de conexiones, más NAT/IP |
| La regla «ya está» y no funciona | Se editó otro SG o la ENI no lo tiene | SG asociados a la ENI | Asociar el SG correcto |
| `RulesPerSecurityGroupLimitExceeded` | Demasiadas reglas | Cuenta de reglas | Lista de prefijos, referencia a SG |
| `InvalidParameterValue` en regla de SG de otra VPC | Referencia a SG de una VPC sin peering | VPC de origen | Peering/TGW o CIDR |
| Tras `terraform apply` se recrean los SG | Cambió `name`/`description` | `plan` | Fijar `name_prefix`/`description` y `lifecycle` |
| `InvalidGroup.Reserved` / «cannot begin with sg-» al crear un SG | AWS reserva el prefijo `sg-` para los IDs | Nombre del grupo | Usa otro prefijo (`tienda-app-`); el nombre amigable va en la etiqueta `Name` |
| No puedo borrar un SG | Referenciado o asociado | `describe-network-interfaces` | Quitar referencias y asociaciones |
