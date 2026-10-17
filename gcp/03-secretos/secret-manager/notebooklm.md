# NotebookLM · Google Cloud · Secret Manager

**Fuentes a subir:** todos los `.md` de esta carpeta y de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Secret Manager en Google Cloud, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. Qué es, con la analogía de casilleros con llave en una oficina y un diagrama de sus piezas.
2. Cómo funciona por dentro, componente por componente: secretos y versiones, alias, replicación automática o administrada, secretos regionales, CMEK, programación de rotación con Pub/Sub, checksum CRC32C, montaje en Cloud Run y GKE.
3. Para qué sirve y cuándo NO usarlo.
4. Conceptos clave explicados en palabras simples: latest, fijar versión, rotación sin caída, accessor, destruir.
5. Seguridad: tabla de identidad, plano de control y plano de datos, y acceso por red privada.
6. Qué hacer y qué NO hacer, límites y costos (con «verifica» en lo que cambia).
7. Los casos reales y el uso desde Java: una caché con TTL y gracia y verificación CRC32C con SecretManagerServiceClient; Spring MVC y WebFlux, Quarkus imperativo y Mutiny.
8. Troubleshooting en orden y repaso con 3 preguntas.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
