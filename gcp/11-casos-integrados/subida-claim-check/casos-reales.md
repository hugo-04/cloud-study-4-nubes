# Google Cloud · Caso integrado · Subida con claim check · Casos reales

## 1. El «PDF» que era un ejecutable
**Qué pasó:** un archivo `catalogo.pdf` de un mayorista de ModaLima era un ejecutable.
**Causa:** antes se validaba por extensión.
**Arreglo:** validación por firma de bytes; rechazado y borrado.
**Lección:** los bytes no mienten; la extensión sí.

## 2. El doble procesamiento
**Qué pasó:** algunas fotos se procesaban dos veces.
**Causa:** reentregas de la notificación.
**Arreglo:** transición condicional `PENDIENTE → RECIBIDA`.
**Lección:** el evento llega al menos una vez.

## 3. El archivo reemplazado a mitad de validación
**Qué pasó:** un cliente de Café Andino resubió el archivo mientras se validaba.
**Causa:** copia sin precondición: se aprobó la versión nueva sin validar.
**Arreglo:** `ifGenerationMatch` con la generación validada.
**Lección:** valida y mueve la misma versión.

## 4. La cuarentena llena
**Qué pasó:** miles de subidas abandonadas ocupaban espacio.
**Causa:** sin ciclo de vida.
**Arreglo:** borrado a 1 día en `cuarentena/`.
**Lección:** lo temporal caduca solo.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Archivo malicioso | Extensión | Firma de bytes |
| 2 | Duplicado | Reentrega | Transición condicional |
| 3 | Versión no validada | Sin precondición | ifGenerationMatch |
| 4 | Basura | Sin ciclo | Ciclo de vida |
