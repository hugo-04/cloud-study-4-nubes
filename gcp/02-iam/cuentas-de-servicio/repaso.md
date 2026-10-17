# Google Cloud · IAM · Cuentas de servicio · Repaso

## Preguntas
1. ¿Qué es una cuenta de servicio?
2. ¿Por qué no usar llaves?
3. ¿Qué rol permite adjuntar una cuenta a un recurso?
4. ¿Y suplantarla?
5. ¿Qué es un agente de servicio?
6. ¿Por qué no la cuenta por defecto de Compute?
7. ¿Cuánto dura un token de acceso por defecto?
8. ¿Qué política de organización bloquea llaves?
9. ¿Qué haces antes de borrar una cuenta?
10. ¿Qué token usas para llamar a un Cloud Run privado?

## Respuestas
1. La identidad de una aplicación.
2. Se filtran, no caducan solas y son difíciles de rotar.
3. `roles/iam.serviceAccountUser`.
4. `roles/iam.serviceAccountTokenCreator`.
5. Una cuenta que Google usa en tu nombre para un servicio.
6. Suele tener `editor` y la comparten muchos recursos.
7. Una hora.
8. `iam.disableServiceAccountKeyCreation`.
9. Deshabilitarla y observar.
10. Un ID token con la audiencia del servicio.

## Ejercicios
1. Diseña las cuentas de servicio de los microservicios de ModaLima.
2. Escribe quién puede desplegar y suplantar cada una.
3. Diseña el procedimiento de limpieza de cuentas sin uso.
