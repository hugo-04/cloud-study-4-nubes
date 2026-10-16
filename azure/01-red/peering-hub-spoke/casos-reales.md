# Azure · Peering y Hub-and-Spoke · Casos reales

## Caso 1 · "dev ve shared, pero qa no ve dev"
- **Problema:** Café Andino peereó `dev`↔`shared` y `qa`↔`shared`. `dev` y `qa` no se veían.
- **Causa:** el peering no es transitivo.
- **Solución:** un hub con firewall que enruta y controla el tráfico entre spokes.
- **Lección:** peering = punto a punto, nada más.

## Caso 2 · El peering que quedó en `Initiated`
- **Problema:** el equipo creó el peering desde la VNet A y nada funcionaba.
- **Causa:** faltaba crear el peering en el sentido B→A.
- **Solución:** crear el otro lado (en Terraform, ambos recursos).
- **Lección:** siempre dos recursos, siempre dos sentidos.

## Caso 3 · VPN compartida por todos los spokes
- **Problema:** cada spoke tenía su propio VPN Gateway hacia la oficina, con costos altos.
- **Solución:** un solo VPN Gateway en el hub con `allow_gateway_transit`, y `use_remote_gateways` en cada spoke.
- **Resultado:** un gateway en vez de seis.
- **Lección:** el hub centraliza lo caro y compartido.

## Caso 4 · Firewall en el medio y respuestas perdidas
- **Problema:** tras forzar el tráfico por el firewall, las conexiones spoke→spoke fallaban a ratos.
- **Causa:** un spoke tenía la Route Table y el otro no: ida por el firewall, vuelta directa (ruteo asimétrico).
- **Solución:** aplicar la Route Table en ambos spokes.
- **Lección:** UDR en los dos lados.

## Caso 5 · Rango solapado con la oficina
- **Problema:** no se podía conectar la oficina al hub.
- **Causa:** el hub usaba `10.0.0.0/16`, igual que la oficina.
- **Solución:** rediseño con `10.50.0.0/16` para el hub y migración.
- **Lección:** el plan de rangos se hace antes, con todos los equipos.
