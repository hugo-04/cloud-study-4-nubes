# Azure · NSG, Rutas y NAT · Casos reales

## Caso 1 · "Puse un Allow y la base seguía abierta a todos"
- **Problema:** ModaLima creó una regla Allow para que `snet-app` llegara al puerto 1433 de `snet-data`. Un auditor demostró que una VM de `snet-web` también llegaba a la base.
- **Causa:** la regla por defecto `AllowVnetInBound` (65000) permite todo lo de la VNet. Faltaba un Deny.
- **Solución:** agregar `deny-vnet-inbound` con prioridad 4000.
- **Lección:** en Azure, "permitir" no es lo mismo que "solo permitir".

## Caso 2 · Salida por el firewall que no volvía
- **Problema:** tras forzar `0.0.0.0/0` hacia el firewall, algunos servicios dejaron de responder.
- **Causa:** ruteo asimétrico. El tráfico de ida pasaba por el firewall, pero la respuesta de un servicio en otra subnet regresaba directo y el firewall la descartaba.
- **Solución:** aplicar la misma Route Table a todas las subnets involucradas y usar reglas de red consistentes.
- **Lección:** al usar UDR, dibuja el camino de ida **y** de vuelta.

## Caso 3 · Timeouts solo en campaña
- **Problema:** durante picos, llamadas al proveedor de pagos fallaban con timeout.
- **Causa:** agotamiento de puertos SNAT: pocas IP de salida y conexiones nuevas por cada petición.
- **Solución:** NAT Gateway con más IP públicas y pool de conexiones HTTP en la aplicación.
- **Lección:** el problema era de capacidad, no de reglas.

## Caso 4 · La IP del proveedor que "cambió"
- **Problema:** el proveedor de pagos pedía una lista de IP permitidas, pero las IP de salida de ModaLima cambiaban.
- **Solución:** NAT Gateway con IP pública **estática**; se entregó esa IP al proveedor.
- **Lección:** si alguien necesita permitir tus IP, necesitas una salida con IP fija.

## Caso 5 · Regla que bloqueaba el diagnóstico
- **Problema:** el equipo no lograba saber por qué una conexión fallaba.
- **Solución:** usar **IP flow verify** (Network Watcher) y vieron la regla exacta que negaba el paquete.
- **Lección:** no adivines; Azure te dice qué regla negó el tráfico.
