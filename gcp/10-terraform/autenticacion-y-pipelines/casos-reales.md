# Google Cloud · Terraform · Autenticación y pipelines · Casos reales

## 1. La llave del CI filtrada
**Qué pasó:** la llave JSON de la SA `terraform` de ModaLima apareció en un log público.
**Causa:** llave como secreto del CI y un `echo` de depuración.
**Arreglo:** WIF, borrar llaves y prohibir su creación.
**Lección:** sin llaves no hay llave que filtrar.

## 2. El PR que aplicó
**Qué pasó:** un PR de un fork intentó un `apply`.
**Causa:** la misma SA para plan y apply.
**Arreglo:** SA de apply solo para `ref=refs/heads/main` con aprobación.
**Lección:** separa lectura y escritura.

## 3. El apply distinto al revisado
**Qué pasó:** en Café Andino el apply hizo un cambio que no estaba en el plan revisado.
**Causa:** el apply re-planificó tras otro merge.
**Arreglo:** aplicar el `plan.bin` guardado del mismo commit.
**Lección:** aplica lo que revisaste.

## 4. La base borrada por un rename
**Qué pasó:** renombrar un recurso en el código planificó destruir y crear Cloud SQL.
**Causa:** nadie vio la línea `destroy` en un plan largo.
**Arreglo:** política sobre `plan.json` que bloquea destrucciones de recursos con datos.
**Lección:** automatiza lo que el ojo pierde.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Llave filtrada | Llave en CI | WIF |
| 2 | Apply desde PR | SA única | Plan/apply separados |
| 3 | Apply distinto | Re-planificación | Plan guardado |
| 4 | Base borrada | Plan largo | Política automática |
