# NotebookLM · Azure · Storage Queues

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/` (Terraform, CLI, KQL, KEDA).

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure Storage Queues, para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes.

Estructura obligatoria:
1. Qué es una Storage Queue, con la analogía de la bandeja de tarjetas con temporizador, y cómo se relaciona con la cuenta de Storage.
2. El ciclo de vida de un mensaje: put, get, visibility timeout, popReceipt, delete, update, peek y clear. Diagrama de tiempos.
3. Garantías y límites: al menos una vez, orden, 64 KB, TTL, 32 por lectura, rendimiento y codificación Base64.
4. dequeueCount, mensajes venenosos y construcción de la cola de veneno; reintentos con retroceso; mensajes diferidos.
5. Storage Queues frente a Service Bus: tabla de decisión y cuándo migrar.
6. Seguridad e IAM: Entra ID sin claves, roles Sender, Processor, Reader y Contributor, red privada y cifrado.
7. Los 10 casos reales como historias con su lección: miniaturas, correos, eventos de Blob, mensajes diferidos, duplicados por visibilidad, cola de veneno sin alerta, escalado con KEDA, migración a Service Bus, mensajes grandes y codificación con Functions.
8. Código Java: productor, trabajador con hilo virtual, renovación de visibilidad, versión reactiva con WebFlux, Azure Functions con disparador de cola, Quarkus con Mutiny.
9. Ejemplos de Terraform, CLI, KQL y KEDA; qué hacer y qué NO hacer; costos y límites.
10. Tabla de troubleshooting y secuencia de diagnóstico.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
