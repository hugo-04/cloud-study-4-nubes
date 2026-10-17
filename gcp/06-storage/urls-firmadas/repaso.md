# Google Cloud · Storage · URLs firmadas · Repaso

## Preguntas
1. ¿Qué es una URL firmada?
2. ¿Cuál es el vencimiento máximo con V4?
3. ¿Cómo se firma sin llave JSON?
4. ¿Se puede revocar una URL?
5. ¿Qué pasa si el cliente cambia una cabecera firmada?
6. ¿Qué permisos usa la URL?
7. ¿Cómo evitas que una subida pise?
8. ¿Qué configuración necesita el bucket para el navegador?
9. ¿Por qué no registrar URLs?
10. ¿Cuándo NO usarlas?

## Respuestas
1. Una URL que autoriza un método sobre un objeto por un tiempo.
2. 7 días.
3. Con `signBlob` de IAM Credentials.
4. No; solo vencer o quitar permisos al firmante.
5. La firma no coincide y falla.
6. Los del firmante.
7. Firmando `x-goog-if-generation-match: 0`.
8. CORS.
9. Son credenciales de portador.
10. Para acceso permanente de sistemas.

## Ejercicios
1. Diseña la subida directa de fotos con nombre, tipo y precondición firmados.
2. Elige vencimientos por caso de uso.
3. Escribe la configuración CORS del bucket.
