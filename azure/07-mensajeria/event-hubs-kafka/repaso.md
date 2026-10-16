# Azure · Event Hubs (Kafka) · Repaso

## Preguntas de repaso
1. ¿Qué es Event Hubs en una frase?
   - *Un log particionado y de solo agregar, para recibir flujos enormes de eventos que varios lectores consumen a su ritmo y que se pueden volver a leer durante la retención.*
2. ¿En qué se diferencia de una cola?
   - *Una cola entrega y borra; el log conserva y cada lector lleva su offset. Se puede rebobinar.*
3. ¿Qué es una partición y qué garantiza?
   - *Un carril ordenado. El orden se garantiza solo dentro de una partición.*
4. ¿Qué decide la clave de partición?
   - *A qué carril va el evento (hash). Misma clave → misma partición → orden para esa clave.*
5. ¿Cuántos consumidores útiles puedo tener en un grupo?
   - *Como máximo uno por partición; los sobrantes quedan ociosos.*
6. ¿Qué es un grupo de consumidores?
   - *Una vista independiente del flujo con sus propios offsets; uno por microservicio.*
7. ¿Qué es un checkpoint y cuándo se hace?
   - *"He procesado hasta aquí". Después de procesar, cada N eventos o T segundos.*
8. ¿Qué garantía de entrega hay y qué implica?
   - *Al menos una vez: puede haber repetidos; el consumidor debe ser idempotente.*
9. ¿Qué son TU, PU y CU?
   - *Unidades de capacidad de Standard, Premium y Dedicated. Auto-inflate sube TU solas, no las baja.*
10. ¿Qué es Capture y cuándo lo usas?
    - *Volcado automático a Blob/Data Lake en Avro; para el lago, auditoría y reprocesos masivos.*
11. ¿Cómo se conecta una aplicación Kafka?
    - *Cambiando `bootstrap.servers` a `<ns>.servicebus.windows.net:9093` y la seguridad a SASL_SSL (OAUTHBEARER con Entra ID o PLAIN con `$ConnectionString`).*
12. ¿Qué es un evento venenoso y qué haces con él?
    - *Uno que siempre falla. No hay DLQ nativa: lo reenvías a un event hub de errores con el motivo y sigues.*
13. ¿Qué es el lag y cómo lo vigilas?
    - *Eventos que le faltan al consumidor para alcanzar al productor; con `AdminClient` o métricas propias y alertas.*
14. ¿Event Hubs, Service Bus o Event Grid?
    - *Flujo masivo y reproducción → Event Hubs; comandos con garantías por mensaje → Service Bus; reaccionar a eventos de Azure con filtros → Event Grid.*
15. ¿Por qué no usarlo como base de datos eterna?
    - *La retención es limitada: el histórico permanente va al lago (Capture) o a una base de datos.*
16. ¿Qué cliente Java elijo?
    - *SDK nativo si es solo Azure y quieres checkpoints/balanceo hechos; cliente Kafka (Spring Kafka, Quarkus) si buscas portabilidad.*
17. ¿Qué pasó con Reactor Kafka?
    - *Fue descontinuado (1.3 es la última); para código nuevo, Spring Kafka con WebFlux en el borde o Quarkus con SmallRye.*

## Entrevista
- Diseña la ingesta de telemetría de 4.000 sensores con alertas en vivo y auditoría de un año. ¿Particiones, clave, grupos, Capture, retención?
- Un consumidor tiene lag creciente solo en una partición. ¿Qué investigas y cómo lo arreglas?
- ¿Cómo garantizas que una factura no se emita dos veces?
- ¿Qué cambia al migrar una aplicación Kafka a Event Hubs y qué debes verificar antes?
- ¿Cómo proteges el namespace: identidad, roles, red y claves?

## Ejercicio práctico
1. Despliega el [Terraform](ejemplos/terraform/main.tf) en Standard.
2. Publica 10.000 eventos con clave `clienteId` (SDK nativo) y mira cómo se reparten por partición.
3. Levanta 2 réplicas del consumidor con `EventProcessorClient` y observa el reparto de particiones; luego 8.
4. Cambia la clave a `region` y observa la partición caliente.
5. Provoca un evento venenoso y comprueba que llega a `errores-clics` sin detener la partición.
6. Reproduce los eventos desde hace una hora con el grupo `reproceso`.
7. Conecta una aplicación Spring Kafka con OAUTHBEARER y compárala con el SDK nativo.
8. Lee un archivo de Capture con el lector Avro.
