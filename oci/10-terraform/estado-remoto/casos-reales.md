# Oracle OCI · Terraform · Estado remoto · Casos reales

## 1. Dos applies, una red rota
**Qué pasó:** dos pipelines de ModaLima aplicaron a la vez sobre la red y dejaron reglas duplicadas.
**Causa:** backend `http` con PAR, sin bloqueo.
**Arreglo:** backend con bloqueo y una sola cola de ejecución por estado.
**Lección:** sin bloqueo, el estado es una carrera.

## 2. La contraseña en el estado
**Qué pasó:** un estado con la contraseña de la base terminó en un repositorio público.
**Causa:** alguien hizo `terraform state pull > estado.json` y lo subió.
**Arreglo:** contraseñas desde Vault (no generadas en Terraform), bucket privado con CMK y escaneo de secretos en el repositorio.
**Lección:** el estado es un secreto más.

## 3. El estado corrupto
**Qué pasó:** un corte de red durante un `apply` dejó un estado incompleto.
**Causa:** sin versionado del bucket.
**Arreglo:** versionado + recuperación de la versión anterior + `import` de lo creado.
**Lección:** versiona el estado desde el día uno.

## 4. El bloqueo fantasma
**Qué pasó:** todos los planes de Café Andino fallaban con «state locked».
**Causa:** un runner murió a mitad de `apply` y el bloqueo quedó.
**Arreglo:** detector de bloqueos viejos y `force-unlock` con el id, tras confirmar que no hay ejecución en curso.
**Lección:** los bloqueos colgados se vigilan, no se borran a ciegas.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Recursos duplicados | Sin bloqueo | Backend con bloqueo |
| 2 | Secreto expuesto | Estado fuera del bucket | Vault + CMK + escaneo |
| 3 | Estado roto | Sin versionado | Versionar |
| 4 | Siempre bloqueado | Runner muerto | Detector + `force-unlock` |
