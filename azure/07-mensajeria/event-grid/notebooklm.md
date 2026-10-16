# NotebookLM · Azure · Event Grid

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure Event Grid, para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes.

Estructura obligatoria:
1. Qué es Event Grid, con la analogía del sistema de altavoces de un edificio, y la diferencia entre evento y mensaje.
2. Las familias: tópicos del sistema, personalizados, dominios, de socio y espacios de nombres con entrega pull y broker MQTT. Diagrama del flujo.
3. Esquemas: Event Grid, CloudEvents y entrada personalizada; anatomía de un CloudEvent de microservicios.
4. Entrega: al menos una vez, orden, reintentos, dead-letter, lotes, tamaño y latencia; el handshake de los webhooks.
5. Destinos y cómo se autentica la entrega con identidad administrada: Service Bus, Storage Queue, Event Hubs, Functions, webhooks.
6. Filtros por tipo, subject y avanzados, con el recetario de operadores.
7. Event Grid frente a Service Bus y Event Hubs, y el patrón Event Grid hacia Service Bus.
8. Seguridad e IAM: publicar con Entra ID, desactivar claves, roles de publicador, suscriptor y de entrega, redes privadas y servicios de confianza.
9. Los 11 casos reales como historias con su lección: rotación de secretos, fan-out, bucles, duplicados, dominios, pull, Container Registry.
10. Código Java: publicador con Entra ID, lotes, dominio multi-cliente, consumo de eventos de Key Vault vía Service Bus, webhook con enrutamiento por tipo e idempotencia, entrega pull de namespaces, versión reactiva con WebFlux y Quarkus con Mutiny.
11. Ejemplos de Terraform, CLI, KQL y eventos JSON; qué hacer y qué NO hacer; costos y límites.
12. Tabla de troubleshooting con las métricas por tramo y la secuencia de diagnóstico.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
