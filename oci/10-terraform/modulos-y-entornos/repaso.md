# Oracle OCI · Terraform · Módulos y entornos · Repaso

## Preguntas
1. ¿Qué es un módulo?
2. ¿Cómo referencias una versión fija?
3. ¿Por qué no usar `workspaces` para prod?
4. ¿Qué debe diferir entre entornos?
5. ¿Qué es la promoción?
6. ¿Para qué `moved`?
7. ¿Qué tamaño ideal tiene la interfaz de un módulo?
8. ¿Qué archivo fija versiones de providers?
9. ¿Qué ofrece Resource Manager aquí?
10. ¿Cómo detectas diferencias no permitidas?

## Respuestas
1. Una carpeta reutilizable de Terraform con variables y salidas.
2. `?ref=vX.Y.Z` o versión del registro.
3. Porque comparten código y permisos; carpetas y estados separados aíslan mejor.
4. Solo variables permitidas (tamaño, réplicas, nombres).
5. Aplicar en prod la misma versión ya probada en no-prod.
6. Renombrar sin destruir.
7. Entre 5 y 10 variables.
8. `.terraform.lock.hcl`.
9. Stacks con variables por entorno, jobs y detección de drift.
10. Comparando variables y versiones de los stacks.

## Ejercicios
1. Diseña la interfaz del módulo `microservicio` de ModaLima.
2. Escribe el bloque `moved` para un renombre de módulo.
3. Define las diferencias permitidas entre prod y no-prod.
