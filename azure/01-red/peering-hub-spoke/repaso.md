# Azure · Peering y Hub-and-Spoke · Repaso

## Preguntas de repaso
1. ¿Por qué el peering debe crearse en los dos sentidos?
   - *Cada VNet tiene su propio recurso de peering; con uno solo queda `Initiated`.*
2. ¿Qué significa "no transitivo"?
   - *A↔B y B↔C no implica A↔C.*
3. ¿Qué hacen `allow_gateway_transit` y `use_remote_gateways`?
   - *El hub comparte su gateway; el spoke lo usa.*
4. ¿Para qué sirve `allow_forwarded_traffic`?
   - *Aceptar tráfico reenviado por un firewall/NVA que no nació en la VNet vecina.*
5. ¿Cuándo prefieres Private Link sobre un peering?
   - *Cuando solo quieres exponer un servicio, no toda la red.*
6. ¿Cuándo usar Virtual WAN?
   - *Muchas sucursales y VNets, con enrutamiento administrado.*
7. ¿Qué haces tras ampliar el address space de una VNet peereada?
   - *Sincronizar el peering.*

## Entrevista
- Diseña un hub-and-spoke para dev, qa y prod donde prod nunca ve a dev.
- ¿Cómo permites que dos spokes hablen a través de un firewall y qué errores esperas?
- ¿Cómo compartes un solo VPN Gateway con seis spokes?
