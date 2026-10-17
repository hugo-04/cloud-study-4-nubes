# Oracle OCI · Secretos · Vault: secretos · Repaso

## Preguntas
1. ¿Qué diferencia hay entre un secreto y una llave de KMS?
2. ¿Qué es una versión? ¿Y una etapa?
3. ¿Para qué sirve `PREVIOUS`?
4. ¿Cómo se rota sin caída?
5. ¿Por qué cachear el secreto?
6. ¿Qué es *stale-if-error*?
7. ¿Qué política necesita la aplicación?
8. ¿Qué riesgo tiene el valor en Terraform?
9. ¿En qué formato llega el contenido?
10. ¿Qué nunca debes registrar?

## Respuestas
1. El secreto entrega un valor a quien lo lee; la llave nunca sale del servicio y se usa para cifrar.
2. Versión: valor inmutable numerado; etapa: su estado (`CURRENT`, `PENDING`…).
3. Mantener la anterior mientras las instancias renuevan su caché.
4. Crear `PENDING`, cambiar la credencial real, promover a `CURRENT`.
5. Para no depender de Vault en cada petición.
6. Usar el valor guardado si la renovación falla.
7. `read secret-bundles` sobre ese secreto.
8. Queda en el estado: protégelo y cámbialo fuera.
9. Base64.
10. El valor del secreto.

## Ejercicios
1. Diseña la rotación de la contraseña de una base con `PENDING`.
2. Define TTL y gracia de caché para un token de proveedor.
3. Escribe la política mínima para `app-tienda`.
