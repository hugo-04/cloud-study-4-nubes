# NotebookLM · Azure · Function Apps

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure Functions (Function Apps), para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes.

Estructura obligatoria:
1. Qué es, con la analogía del taxi por viaje; función, Function App, trigger y binding.
2. Cómo funciona por dentro: host, worker de Java, extensiones, cuenta de Storage del host y scale controller. Dibuja el flujo de un evento hasta tu método.
3. Los planes de alojamiento (Flex Consumption, Premium, Dedicated, Consumption clásico, Container Apps) y cuándo elegir cada uno.
4. Triggers y bindings más usados con sus anotaciones Java, y la semántica de entrega al menos una vez.
5. Reintentos, mensajes envenenados y DLQ; qué triggers admiten directivas de reintento y cuáles no.
6. Durable Functions: orquestador determinista, actividades, cliente, replay y los patrones (encadenado, fan-out/fan-in, API asíncrona, monitor, humano).
7. Identidad y conexiones sin cadenas (sufijo doble guion bajo), roles necesarios y seguridad de HTTP.
8. Red: Private Endpoint, VNet Integration y triggers con recursos privados.
9. Los 9 casos reales como historias con su lección.
10. Código Java: HTTP, Service Bus con idempotencia, timer, blob con Event Grid, Event Hubs por lotes, Durable, host.json, clientes compartidos, y cómo encajan Spring y Quarkus; por qué no devolver Mono/Uni.
11. Ejemplos de CLI, Terraform y GitHub Actions.
12. Qué hacer, qué NO hacer, límites y la tabla de troubleshooting.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
