# Oracle OCI · Storage · Object Storage · Casos reales

## 1. El comprobante pisado
**Qué pasó:** dos reintentos de la misma compra generaron PDFs distintos y el segundo reemplazó al primero, ya enviado al cliente.
**Causa:** `PUT` sin condición.
**Arreglo:** nombre determinista `pedidos/AAAA/MM/DD/<id>.pdf` + `If-None-Match: *`; si ya existe, se reutiliza.
**Lección:** el almacenamiento también necesita idempotencia.

## 2. El bucket público de una tarde
**Qué pasó:** para «probar rápido», un bucket de ModaLima se hizo público y quedó así tres meses con exportes de clientes.
**Causa:** visibilidad cambiada a mano.
**Arreglo:** buckets como código, alarma ante `UpdateBucket` con `publicAccessType` y PAR para compartir.
**Lección:** lo temporal se vuelve permanente.

## 3. La factura del respaldo
**Qué pasó:** los respaldos diarios de Café Andino crecían 2 TB al mes en `Standard`.
**Causa:** sin reglas de ciclo de vida.
**Arreglo:** `Archive` a los 30 días y borrado a los 400 (con retención para lo legal).
**Lección:** define el ciclo de vida al crear el bucket.

## 4. La subida que nunca terminaba
**Qué pasó:** los exportes de 3 GB fallaban por cortes de red.
**Causa:** un único `PUT`.
**Arreglo:** `UploadManager` con multipart y reintentos por parte.
**Lección:** lo grande se sube en partes.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Objeto reemplazado | `PUT` sin condición | Nombre determinista + `If-None-Match` |
| 2 | Datos expuestos | Bucket público | Privado + PAR + alarma |
| 3 | Costo creciente | Sin ciclo de vida | Archive y borrado |
| 4 | Subidas fallidas | Objeto grande | Multipart |
