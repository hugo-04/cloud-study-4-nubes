# Azure · Service Bus · Repaso

## Preguntas de repaso
1. ¿Qué es Service Bus y qué garantiza?
   - *Un broker empresarial: entrega confiable al menos una vez, reintentos, DLQ, duplicados, orden por sesión y publicación a varios suscriptores.*
2. ¿Cola o tópico?
   - *Cola: un mensaje lo trata un consumidor (comandos). Tópico: cada suscripción recibe su copia (eventos).*
3. ¿Qué es peek-lock y por qué es el modo correcto?
   - *Bloquea el mensaje al recibirlo y se borra solo al completarlo; sin pérdida si el consumidor falla.*
4. ¿Cuándo `complete`, `abandon`, `deadLetter` y `defer`?
   - *Éxito; fallo transitorio; fallo permanente; esperar a otro mensaje.*
5. ¿Qué es la DLQ y cuándo se llena?
   - *Subcola de fallidos: entregas máximas, TTL vencido, dead-letter explícito o error de filtro.*
6. ¿Cómo evitas el cobro doble?
   - *Idempotencia en el consumidor (clave única), `MessageId` estable y duplicate detection.*
7. ¿Cómo garantizas orden?
   - *Sesiones con `SessionId` (FIFO por clave y un consumidor por sesión).*
8. ¿Qué tipos de filtro existen y cuál es más barato?
   - *Booleano, SQL y correlación; correlación es el más rápido.*
9. ¿Qué pasa con `$Default`?
   - *Es el filtro "todo"; si no lo reemplazas, la suscripción recibe todo (reglas con OR).*
10. ¿Cómo haces reintentos con espera?
    - *Reenviar una copia programada (con MessageId nuevo) y completar el original.*
11. ¿Qué problema resuelve Outbox?
    - *Falta de transacción BD+broker: se guarda el mensaje en la BD y se publica después.*
12. ¿Qué hace `lockDuration` y cómo evitas perder el bloqueo?
    - *Tiempo de bloqueo; usa renovación automática, prefetch bajo y bloqueo adecuado.*
13. ¿Qué roles necesitan productor y consumidor?
    - *Azure Service Bus Data Sender / Data Receiver, en la entidad.*
14. ¿Cuándo Premium?
    - *Red privada, mensajes grandes, rendimiento predecible, CMK, zonas, Geo-DR/JMS.*
15. ¿Cuándo NO Service Bus?
    - *Streaming masivo (Event Hubs), notificaciones ligeras (Event Grid), cola trivial (Storage Queue), archivos (Claim Check).*

## Entrevista
- Diseña la mensajería de un e-commerce: pedido, pago, inventario, envío, notificaciones.
- Un consumidor procesa mensajes dos veces. ¿Cuáles son las tres causas posibles?
- ¿Cómo recuperas 50 000 mensajes de la DLQ sin duplicar efectos?
- ¿Sesiones o particionar por clave? Compara con Kafka.

## Ejercicio práctico
1. Levanta el [emulador](ejemplos/emulator/docker-compose.yaml) y la configuración de ejemplo.
2. Envía mensajes con el productor de [uso en Java](uso-en-java.md) y consume con el consumidor idempotente.
3. Envía un JSON inválido y comprueba el *dead-letter* con motivo.
4. Prueba el mismo `MessageId` dos veces y observa el descarte.
5. Crea las reglas del tópico y verifica qué suscripción recibe qué.
6. Despliega el [Terraform](ejemplos/terraform/main.tf) y dispara la alerta de DLQ.
