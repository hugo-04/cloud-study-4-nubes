# NotebookLM · AWS · URLs prefirmadas de S3

**Fuentes a subir:** los `.md` de esta carpeta y `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre las URLs prefirmadas de Amazon S3, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. La analogía del boleto de cine y el flujo cliente → backend → S3.
2. Cómo funciona: firma SigV4 en local, parámetros de la URL, permisos del firmante en el momento de uso, caducidad (usuario IAM frente a rol), cabeceras firmadas, POST prefirmado con política y límite de tamaño.
3. Cuándo usarlas y cuándo no (frente a CloudFront y a pasar por la API).
4. Seguridad: la URL como secreto, vida corta, clave elegida por el backend, validación posterior, políticas de bucket que bloquean al cliente.
5. Qué hacer y qué no.
6. Los seis casos reales como historias con su lección.
7. Java: S3Presigner para PUT y GET, firma manual del POST con la derivación de clave SigV4, caducidad efectiva, política de subida, Spring MVC y WebFlux, Quarkus imperativo y Mutiny.
8. Troubleshooting: SignatureDoesNotMatch, caducidad, CORS.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
