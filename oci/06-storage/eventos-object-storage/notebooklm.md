# NotebookLM · Oracle OCI · Eventos de Object Storage

**Fuentes a subir:** todos los `.md` de esta carpeta y de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Eventos de Object Storage en Oracle OCI, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. Qué es, con la analogía de el timbre con cámara de la casa y un diagrama de sus piezas.
2. Cómo funciona por dentro, componente por componente: eventos del bucket, tipos createobject/updateobject/deleteobject, reglas de Events con condición JSON, acciones a Functions/Notifications/Streaming, formato CloudEvents.
3. Para qué sirve y cuándo NO usarlo.
4. Conceptos clave explicados en palabras simples: eventID, al menos una vez, idempotencia, ciclo de eventos.
5. Seguridad: tabla de identidad, plano de control y plano de datos, y acceso por red privada.
6. Qué hacer y qué NO hacer, límites y costos (con «verifica» en lo que cambia).
7. Los casos reales y el uso desde Java: un consumidor que filtra, deduplica por eventID y verifica el objeto con headObject; Spring MVC y WebFlux, Quarkus imperativo y Mutiny.
8. Troubleshooting en orden y repaso con 3 preguntas.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
