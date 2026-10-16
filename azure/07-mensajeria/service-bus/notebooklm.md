# NotebookLM · Azure · Service Bus

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure Service Bus, para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes.

Estructura obligatoria:
1. Qué es Service Bus, con la analogía de la oficina de correos con buzón de devoluciones, y para qué sirve un broker de mensajes.
2. Jerarquía: namespace, colas, tópicos, suscripciones, reglas y DLQ; niveles Basic, Standard y Premium.
3. Anatomía del mensaje y el ciclo de vida completo con peek-lock: complete, abandon, deadLetter, defer, bloqueo y expiración. Dibuja el diagrama.
4. Las funciones clave: DLQ, máximo de entregas, detección de duplicados, sesiones, mensajes programados, TTL, transacciones, auto-forward, filtros y acciones, particionamiento.
5. Las reglas para consumir bien: idempotencia, bloqueo, liquidar siempre, clasificar errores, prefetch, concurrencia, lotes, reutilizar clientes.
6. Filtros de suscripción: booleano, SQL y correlación, y la trampa de la regla $Default.
7. Cuándo usar Service Bus y cuándo no: Event Hubs, Event Grid, Storage Queue, Claim Check y Outbox.
8. Seguridad e IAM: Entra ID, desactivar claves, roles por entidad, Private Endpoint en Premium, diagnóstico.
9. Los 11 casos reales como historias con su lección.
10. Código Java: fábrica de clientes, productor con lotes y mensajes programados, consumidor idempotente con reintentos con espera, transacciones entre entidades, sesiones, administración de reglas, reproceso de DLQ, versión reactiva con Reactor y WebFlux, y Quarkus con Mutiny; emulador local.
11. Ejemplos de Terraform, CLI, KQL y emulador; qué hacer y qué NO hacer; costos y límites.
12. Tabla de troubleshooting, la secuencia de diagnóstico y el procedimiento para reprocesar una DLQ.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
