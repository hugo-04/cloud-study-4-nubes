# Oracle OCI · Terraform · Módulos y entornos · Casos reales

## 1. El módulo que cambió solo
**Qué pasó:** un `apply` de rutina en prod de ModaLima recreó los NSG.
**Causa:** el módulo se referenciaba con `ref=main` y alguien había cambiado la rama.
**Arreglo:** `ref=vX.Y.Z` y promoción explícita de versión.
**Lección:** fija versiones.

## 2. Prod distinto de no-prod
**Qué pasó:** un error de red solo pasaba en prod.
**Causa:** prod tenía una regla agregada a mano en su carpeta que no existía en no-prod.
**Arreglo:** misma composición con variables; comparación automática de entornos.
**Lección:** los entornos deben diferir solo en lo permitido.

## 3. El renombre que borró la base
**Qué pasó:** renombrar `module.db` a `module.base_datos` planificó destruir y crear la base de Café Andino.
**Causa:** cambio de dirección sin `moved`.
**Arreglo:** bloque `moved` y revisión del `plan` antes de aplicar.
**Lección:** refactorizar código de infraestructura requiere `moved`.

## 4. El módulo de 80 variables
**Qué pasó:** nadie entendía el módulo «plataforma».
**Causa:** todo en un módulo.
**Arreglo:** dividir en `red-base`, `microservicio`, `datos`.
**Lección:** interfaces pequeñas.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Cambios inesperados | `ref=main` | Versión fija |
| 2 | Fallo solo en prod | Cambios manuales | Comparar entornos |
| 3 | Recreación peligrosa | Renombre sin `moved` | `moved` |
| 4 | Módulo inmanejable | Demasiado grande | Dividir |
