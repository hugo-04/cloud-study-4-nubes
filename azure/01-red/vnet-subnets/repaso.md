# Azure · VNet y Subnets · Repaso

## Preguntas de repaso
1. ¿Cuántas IP útiles tiene una subnet `/24` en Azure y por qué?
   - *251: Azure reserva 5.*
2. ¿Una VNet es regional o global? ¿Y una subnet?
   - *Regional las dos; la subnet abarca todas las zonas de la región.*
3. ¿Qué es una subnet delegada y para qué servicios se usa?
   - *Una subnet reservada para que un servicio (App Service, PostgreSQL Flexible, Container Apps) la administre.*
4. Nombra tres subnets con nombre obligatorio.
   - *`GatewaySubnet`, `AzureFirewallSubnet`, `AzureBastionSubnet`.*
5. ¿Por qué conviene una subnet solo para Private Endpoints?
   - *Orden, reglas de red propias y menos riesgo de agotar IP de aplicación.*
6. ¿Qué rol necesita alguien para crear redes sin ser Owner?
   - *Network Contributor sobre el Resource Group.*
7. ¿Qué cobra Azure por la VNet misma?
   - *Nada; se cobran los servicios de red que pones dentro y el tráfico saliente/entre regiones.*
8. ¿Qué hace `default_outbound_access_enabled = false`?
   - *Desactiva la salida implícita; hay que definir salida explícita (NAT Gateway).*

## Entrevista
- Diseña los rangos IP para tres entornos que luego se conectarán entre sí y con una oficina.
- ¿Cómo evitas que la subnet de AKS se llene en una campaña?
- Explica por qué la JVM puede seguir usando una IP vieja tras un failover y cómo lo mitigas.
