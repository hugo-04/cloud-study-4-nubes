# Google Cloud · Fundamentos · Repaso

## Preguntas
1. ¿Cuál es la jerarquía de recursos?
2. ¿Qué diferencia hay entre ID, nombre y número de proyecto?
3. ¿Qué servicios son globales, regionales y zonales?
4. ¿Qué es ADC y en qué orden busca credenciales?
5. ¿Por qué evitar llaves JSON?
6. ¿Qué es la suplantación de una cuenta de servicio?
7. ¿Para qué sirven las políticas de organización?
8. ¿Diferencia entre labels y tags?
9. ¿Qué hay que hacer antes de usar un servicio en un proyecto?
10. ¿Un presupuesto detiene el gasto?

## Respuestas
1. Organización → carpetas → proyectos → recursos.
2. El ID es único e inmutable; el nombre es visible y editable; el número lo asigna Google.
3. VPC/IAM/balanceador HTTPS globales; subredes/Cloud Run/Cloud SQL regionales; VMs/discos zonales.
4. Credenciales por defecto: variable de entorno, `gcloud` local y servidor de metadatos.
5. Se filtran, no expiran solas y son difíciles de rotar.
6. Obtener tokens de otra cuenta de servicio sin su llave, con permiso `serviceAccountTokenCreator`.
7. Imponer restricciones a toda la jerarquía (regiones, IP públicas, llaves).
8. Labels organizan y aparecen en costos; tags se usan en condiciones de IAM y políticas.
9. Habilitar su API.
10. No; solo alerta.

## Ejercicios
1. Diseña la jerarquía de carpetas y proyectos de ModaLima.
2. Elige qué políticas de organización activar el día 1.
3. Explica cómo obtiene credenciales un pod de GKE con Workload Identity.
