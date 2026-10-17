# AWS · IRSA y Pod Identity · Repaso

## Preguntas
1. ¿Por qué no usar el rol del nodo para la aplicación?
   - *Lo comparten todos los pods; es demasiado amplio.*
2. ¿Qué condiciones fija la confianza de IRSA?
   - *`sub` (namespace:serviceaccount) y `aud` (`sts.amazonaws.com`).*
3. ¿Qué operación de STS usa IRSA?
   - *`AssumeRoleWithWebIdentity`.*
4. ¿Qué principal confía en Pod Identity?
   - *`pods.eks.amazonaws.com`.*
5. ¿Qué ventaja tiene Pod Identity al reutilizar un rol entre clústeres?
   - *La confianza no cambia; solo creas una asociación.*
6. ¿Qué mecanismo funciona en Fargate?
   - *IRSA.*
7. ¿Qué variables inyecta IRSA?
   - *`AWS_ROLE_ARN` y `AWS_WEB_IDENTITY_TOKEN_FILE`.*
8. ¿Cómo evitas que un pod alcance el IMDS?
   - *IMDSv2 con límite de saltos 1.*
9. ¿Cuál es la diferencia entre rol de tarea y de ejecución en ECS?
   - *Tarea: lo usa tu código; ejecución: lo usa ECS para imagen y logs.*
10. ¿Cómo compruebas qué identidad usa un pod?
    - *`GetCallerIdentity` desde el pod.*

## Ejercicios
1. Crea un rol con Pod Identity para un servicio que lee una cola.
2. Escribe la confianza IRSA para el ServiceAccount `facturas/facturador`.
3. Escribe el manifiesto de un Deployment con su ServiceAccount.
4. Verifica la identidad desde dentro del pod.

## Autoevaluación
- [ ] Sé elegir entre IRSA y Pod Identity.
- [ ] Sé qué falla cuando el pod usa el rol del nodo.
- [ ] Sé cerrar el IMDS a los pods.
- [ ] Sé explicar la cadena de credenciales del SDK.
