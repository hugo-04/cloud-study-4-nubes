# Oracle OCI · Terraform · Autenticación y pipelines · Repaso

## Preguntas
1. ¿Qué modos de autenticación tiene el provider?
2. ¿Qué usas para un runner dentro de OCI?
3. ¿Y para uno externo?
4. ¿Por qué una identidad por entorno?
5. ¿Qué es aplicar un plan guardado?
6. ¿Cada cuánto rotar llaves?
7. ¿Qué haces si se filtra una llave?
8. ¿Dónde se modifican recursos de IAM?
9. ¿Qué controles corren en cada PR?
10. ¿Qué ofrece Resource Manager para pipelines?

## Respuestas
1. API key, instance principal, resource principal, security token y workload identity.
2. Instance principal (o resource/workload identity).
3. Usuario de servicio con API key rotada.
4. Para que un error en un entorno no pueda afectar otro.
5. Ejecutar `apply` sobre el archivo de `plan -out` revisado.
6. 90 días o menos.
7. Revocarla de inmediato y luego investigar.
8. En la región *home*.
9. `fmt`, `validate`, `tflint`, escaneo de seguridad y `plan`.
10. Jobs de plan y apply con estado administrado.

## Ejercicios
1. Diseña identidades y políticas de runners para ModaLima.
2. Escribe el pipeline con aprobación manual en prod.
3. Escribe el procedimiento de rotación de una API key sin corte.
