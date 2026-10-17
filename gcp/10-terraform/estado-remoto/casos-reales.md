# Google Cloud · Terraform · Estado remoto · Casos reales

## 1. Dos apply a la vez
**Qué pasó:** dos ramas de ModaLima aplicaron red a la vez y el estado quedó con recursos duplicados.
**Causa:** estado local en cada runner.
**Arreglo:** backend `gcs` con bloqueo y un único pipeline por componente.
**Lección:** el candado no es opcional.

## 2. El estado corrupto
**Qué pasó:** un `state rm` equivocado «olvidó» la base de datos.
**Causa:** error humano.
**Arreglo:** restaurar la versión anterior del objeto del bucket.
**Lección:** versionado desde el día uno.

## 3. La contraseña en el estado
**Qué pasó:** un desarrollador de Café Andino leyó la contraseña de la base en el `.tfstate`.
**Causa:** el bucket permitía lectura a todo el proyecto.
**Arreglo:** acceso solo a la SA del pipeline e IAM auth en la base.
**Lección:** el estado es un secreto.

## 4. El candado huérfano
**Qué pasó:** el pipeline se canceló y los siguientes fallaban con «state locked».
**Causa:** el runner murió sin liberar el `.tflock`.
**Arreglo:** confirmar que no hay ejecución activa y `force-unlock <id>`.
**Lección:** verifica antes de desbloquear.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Duplicados | Sin bloqueo | Backend gcs |
| 2 | Recursos olvidados | Error humano | Versión anterior |
| 3 | Secreto leído | Bucket abierto | Acceso mínimo |
| 4 | Bloqueado | Runner muerto | force-unlock |
