# Azure · NSG, Rutas y NAT · Repaso

## Preguntas de repaso
1. ¿Qué regla gana si dos coinciden con el mismo paquete?
   - *La de menor número de prioridad; ahí se deja de evaluar.*
2. ¿Por qué no basta una regla Allow para aislar la subnet de datos?
   - *Porque `AllowVnetInBound` (65000) permite todo lo de la VNet; hace falta un Deny.*
3. Si hay NSG en la subnet y en la NIC, ¿cómo se evalúa el tráfico entrante?
   - *Primero el de la subnet, luego el de la NIC; ambos deben permitir.*
4. ¿Qué es un service tag y por qué es mejor que una lista de IP?
   - *Grupo de IP de un servicio de Azure mantenido por Microsoft; no tienes que actualizarlo.*
5. ¿Qué gana cuando dos rutas coinciden?
   - *La del prefijo más largo; a igual prefijo, UDR > BGP > sistema.*
6. ¿Qué problema resuelve el NAT Gateway?
   - *Salida con IP fija y agotamiento de puertos SNAT.*
7. ¿Qué es el ruteo asimétrico y qué síntoma da?
   - *Ida y vuelta por caminos distintos; el firewall descarta la respuesta y ves timeouts.*
8. ¿Con qué comando ves la regla exacta que bloquea un paquete?
   - *`az network watcher test-ip-flow`.*

## Entrevista
- Diseña las reglas para que solo la API llegue a la base y solo la web llegue a la API.
- Todo el tráfico de salida debe pasar por un firewall: ¿qué configuras y qué riesgos revisas?
- ¿Cómo reduces timeouts en picos por SNAT desde la red y desde el código?
