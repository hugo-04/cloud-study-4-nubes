# NotebookLM · Oracle OCI · Streaming

**Fuentes a subir:** todos los `.md` de esta carpeta y de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Streaming en Oracle OCI, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. Qué es, con la analogía de la grabación de las cámaras de una tienda y un diagrama de sus piezas.
2. Cómo funciona por dentro, componente por componente: stream pools con endpoint privado y configuración Kafka, streams y particiones, claves, offsets, cursores, grupos de consumidores, retención.
3. Para qué sirve y cuándo NO usarlo.
4. Conceptos clave explicados en palabras simples: clave de partición, partición caliente, lag, commit de offset, al menos una vez.
5. Seguridad: tabla de identidad, plano de control y plano de datos, y acceso por red privada.
6. Qué hacer y qué NO hacer, límites y costos (con «verifica» en lo que cambia).
7. Los casos reales y el uso desde Java: un productor por lotes que reintenta solo las entradas fallidas con StreamClient, y la configuración de Spring Kafka; Spring MVC y WebFlux, Quarkus imperativo y Mutiny.
8. Troubleshooting en orden y repaso con 3 preguntas.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
