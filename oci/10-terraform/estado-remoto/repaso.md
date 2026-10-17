# Oracle OCI · Terraform · Estado remoto · Repaso

## Preguntas
1. ¿Qué guarda el estado?
2. ¿Qué opciones de backend hay en OCI?
3. ¿Por qué el estado es un secreto?
4. ¿Para qué sirve el bloqueo?
5. ¿Para qué el versionado del bucket?
6. ¿Cómo separas entornos en un mismo bucket?
7. ¿Qué ofrece Resource Manager?
8. ¿Cómo cambias la dirección de un recurso sin recrearlo?
9. ¿Qué es drift?
10. ¿Qué haces con un bloqueo colgado?

## Respuestas
1. Qué recursos gestiona Terraform, sus IDs y atributos.
2. `oci` nativo, `s3` compatible, `http` con PAR y Resource Manager.
3. Contiene valores sensibles en claro.
4. Evitar ejecuciones simultáneas.
5. Recuperar una versión anterior.
6. Con claves por entorno y políticas por prefijo.
7. Estado, bloqueo, ejecución de jobs y detección de drift administrados.
8. Con bloques `moved`.
9. Diferencia entre estado y realidad.
10. Confirmar que no hay ejecución y `force-unlock` con el id.

## Ejercicios
1. Diseña las claves de estado de ModaLima por componente y entorno.
2. Escribe la política que limita el pipeline de no-prod a su prefijo.
3. Escribe el procedimiento de recuperación de un estado corrupto.
