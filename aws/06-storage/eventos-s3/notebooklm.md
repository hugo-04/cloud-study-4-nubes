# NotebookLM · AWS · Eventos de S3

**Fuentes a subir:** los `.md` de esta carpeta y `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre los eventos de Amazon S3, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. La analogía del timbre de la bodega y el diagrama de destinos.
2. Notificaciones de eventos frente a EventBridge: destinos, filtros, extras; tipos de evento; el contenido del evento y la clave codificada como URL.
3. Garantías: al menos una vez, sin orden, sequencer, recursión.
4. Cuándo usarlos y cuándo no; relación con el patrón Claim Check.
5. Seguridad: políticas del destino con SourceArn y SourceAccount, KMS, validación del evento.
6. Los seis casos reales como historias con su lección.
7. Java: parseo de notificaciones y de EventBridge sin depender de Jackson, decodificación de claves, deduplicación y orden por sequencer, filtro anti-recursión, manejador de Lambda con respuesta parcial de lote, Spring (MVC y WebFlux con @SqsListener) y Quarkus (Lambda y Mutiny).
8. Troubleshooting en orden.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
