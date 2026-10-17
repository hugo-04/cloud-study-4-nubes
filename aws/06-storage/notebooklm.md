# NotebookLM · AWS · Capítulo 06 Storage

**Fuentes a subir:** este `README.md` y los `README.md`, `casos-reales.md` y `uso-en-java.md` de `s3`, `urls-prefirmadas`, `claim-check`, `eventos-s3` y `efs`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, sobre el almacenamiento de archivos y su movimiento en AWS: Amazon S3, URLs prefirmadas, el patrón Claim Check, eventos de S3 y Amazon EFS. Habla solo de AWS; no compares con otras nubes.

Estructura obligatoria:
1. La cadena cliente → URL prefirmada → S3 → evento → cola con ticket → consumidor, con las analogías del texto (bodega, boleto, guardarropa, timbre, carpeta compartida).
2. S3: buckets, objetos, claves, clases de almacenamiento, versionado, ciclo de vida, cifrado con KMS y Bucket Key, Block Public Access, multiparte, checksums, escrituras condicionales.
3. URLs prefirmadas: firma local, permisos del firmante, caducidad con roles, cabeceras firmadas, POST con límite de tamaño, CORS.
4. Claim Check: por qué existe (tamaños máximos de mensajes), ticket con versionId y SHA-256, orden «subir y luego publicar», idempotencia, DLQ y retenciones, confused deputy.
5. Eventos de S3: notificaciones frente a EventBridge, garantías (duplicados, sin orden, sequencer), recursión, clave codificada, políticas del destino.
6. EFS: NFS, mount targets, puntos de acceso, throughput elástico, ciclo de vida, cuándo no usarlo.
7. Árbol de decisión «quiero…», comparativa S3 frente a EFS y receta ModaLima.
8. Casos reales de cada servicio como historias con su lección.
9. Java: claves seguras, plan de partes, firma de URLs y POST, ticket y consumidor idempotente, lector de eventos, rutas seguras y sondas de EFS; versiones imperativas (Spring MVC, Quarkus) y reactivas (WebFlux, Mutiny).
10. Seguridad y errores típicos (bucket público, AccessDenied con KMS, SignatureDoesNotMatch, bucle de eventos).

Reglas: no omitas tablas ni casos; define cada término técnico al usarlo; usa ModaLima y Café Andino como empresas de ejemplo; cierra con 7 puntos de resumen y 5 preguntas de repaso.
```
