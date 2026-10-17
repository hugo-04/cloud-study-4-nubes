# Google Cloud · Mensajería · Managed Kafka · Casos reales

## 1. El cliente que no conectaba
**Qué pasó:** el consumidor de ModaLima fallaba con timeouts al bootstrap.
**Causa:** el clúster publicaba endpoints en otra subred y el firewall no abría 9092.
**Arreglo:** subred del cliente en la configuración del clúster y regla de firewall.
**Lección:** es privado: primero red.

## 2. «SaslAuthenticationException»
**Qué pasó:** en GKE el productor fallaba al autenticarse.
**Causa:** faltaba la biblioteca del login handler o el rol `managedkafka.client`.
**Arreglo:** dependencia en el classpath + rol a la cuenta federada del pod.
**Lección:** OAUTHBEARER necesita ambas cosas.

## 3. El orden perdido
**Qué pasó:** los eventos de un mismo pedido de Café Andino llegaban desordenados.
**Causa:** se producía sin clave.
**Arreglo:** clave = id del pedido.
**Lección:** el orden es por partición, y la partición la decide la clave.

## 4. Lag que no baja
**Qué pasó:** el clickstream acumulaba millones de mensajes de lag.
**Causa:** 12 particiones y 30 consumidores: 18 inactivos; el cuello estaba en la escritura a la base.
**Arreglo:** lotes hacia la base y más particiones planificadas.
**Lección:** consumidores > particiones no ayuda.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Timeout | Red/firewall | Subred + 9092 |
| 2 | Error SASL | Handler/rol | Dependencia + IAM |
| 3 | Desorden | Sin clave | Clave por entidad |
| 4 | Lag | Particiones/destino | Lotes + particiones |
