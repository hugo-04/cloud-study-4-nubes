# Oracle OCI · Storage · Claim check · Casos reales

## 1. Los pedidos mayoristas rechazados
**Qué pasó:** los pedidos mayoristas de ModaLima (miles de líneas) fallaban al encolarse.
**Causa:** superaban el tamaño máximo de mensaje de la cola.
**Arreglo:** sobre híbrido: `INLINE` hasta 64 KB, `REFERENCIA` por encima.
**Lección:** diseña para el mensaje más grande, no para el promedio.

## 2. El ticket sin abrigo
**Qué pasó:** el consumidor recibía tickets cuyo objeto no existía.
**Causa:** el productor enviaba el ticket y luego subía el objeto en paralelo.
**Arreglo:** subir, esperar la confirmación y recién enviar.
**Lección:** el orden de escritura es parte del contrato.

## 3. El reintento que no encontraba nada
**Qué pasó:** al reintentar un mensaje fallido, la carga ya no estaba.
**Causa:** el consumidor borraba el objeto antes de terminar.
**Arreglo:** que el ciclo de vida borre a los 7 días; el consumidor no borra.
**Lección:** el reintento necesita la carga intacta.

## 4. El archivo cambiado
**Qué pasó:** un proceso de Café Andino reescribió un objeto de cargas para «corregirlo».
**Causa:** el consumidor procesó una versión distinta a la enviada.
**Arreglo:** huella SHA-256 en el ticket y verificación al leer; bucket con retención corta que impide sobrescribir.
**Lección:** el ticket debe garantizar *qué* se envió.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Mensajes rechazados | Tamaño | Sobre híbrido |
| 2 | Objeto no encontrado | Orden invertido | Subir antes de enviar |
| 3 | Reintento sin carga | Borrado temprano | Ciclo de vida |
| 4 | Contenido distinto | Objeto modificado | SHA-256 |
