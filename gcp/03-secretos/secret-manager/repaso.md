# Google Cloud · Secretos · Secret Manager · Repaso

## Preguntas
1. ¿Qué es una versión de un secreto?
2. ¿Qué estados tiene una versión?
3. ¿Qué hace la programación de rotación?
4. ¿Qué rol lee el valor?
5. ¿Por qué cachear?
6. ¿Qué replicaciones hay?
7. ¿Para qué el CRC32C?
8. ¿Cuándo NO usar Secret Manager?
9. ¿Qué pasos tiene una rotación sin caída?
10. ¿Cómo auditas las lecturas?

## Respuestas
1. Un valor inmutable del secreto.
2. Habilitada, deshabilitada y destruida.
3. Publica un aviso en Pub/Sub; tú implementas el cambio.
4. `roles/secretmanager.secretAccessor`.
5. Por latencia, costo y cuotas.
6. Automática y administrada por el usuario (y secretos regionales).
7. Verificar integridad.
8. Para configuración no sensible o datos grandes.
9. Versión nueva, doble validez, cambio de consumidores, retiro de la vieja.
10. Con Data Access logs.

## Ejercicios
1. Diseña la rotación de la contraseña de la base de pedidos.
2. Escribe la política IAM de los secretos de ModaLima por servicio.
3. Elige TTL y gracia de la caché del checkout.
