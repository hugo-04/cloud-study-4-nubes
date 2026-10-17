# AWS · Caso integrado · Subida con Claim Check · Casos reales

## 1. El «PDF» que era un ejecutable
**Qué pasó:** un socio subió `boleta.pdf` que en realidad era otro tipo de archivo; el sistema lo aceptó por la extensión y un proceso posterior falló.
**Arreglo:** validar la firma (`%PDF-`) contra el tipo declarado y rechazar con motivo.
**Lección:** la extensión y el `Content-Type` los controla quien sube.

## 2. 403 al subir
**Qué pasó:** el front enviaba `application/octet-stream` pero la URL se firmó con `application/pdf`.
**Causa:** la firma incluye `Content-Type`.
**Arreglo:** la respuesta de la API incluye `contentType` y el front lo copia tal cual.
**Lección:** lo firmado debe coincidir byte a byte.

## 3. El evento que nunca llegó
**Qué pasó:** 6 cargas quedaron `PENDIENTE` para siempre aunque el archivo estaba en S3; la regla de EventBridge había sido desactivada en un cambio.
**Arreglo:** el reconciliador revisa `PENDIENTE` vencidos: si el objeto existe, lo revalida.
**Lección:** los eventos son avisos, no la fuente de verdad.

## 4. Borrado demasiado pronto
**Qué pasó:** el validador copiaba, borraba la cuarentena y luego actualizaba el estado; un fallo en el medio dejó `SUBIDO` sin objeto: el reintento fallaba para siempre.
**Arreglo:** copiar → transición condicional → borrar; la limpieza final es tolerante y respaldada por el ciclo de vida.
**Lección:** el orden de las operaciones es parte del diseño.

## 5. El enlace compartido por WhatsApp
**Qué pasó:** un usuario reenvió su URL de descarga y otra persona vio su boleta.
**Arreglo:** URLs de 5 minutos, generadas bajo demanda para el dueño, nunca guardadas.
**Lección:** una URL prefirmada es una llave temporal: trátala como tal.

## 6. La factura de la basura
**Qué pasó:** miles de subidas abandonadas llenaron la cuarentena.
**Arreglo:** regla de ciclo de vida a 1 día y `AbortIncompleteMultipartUpload`; estado `EXPIRADO`.
**Lección:** lo que no se limpia solo, se acumula.

## Resumen
| # | Síntoma | Pieza que lo evita |
|---|---|---|
| 1 | Archivo disfrazado | Validación de firma en cuarentena |
| 2 | 403 en la subida | `contentType` devuelto por la API |
| 3 | Cargas atascadas | Reconciliador |
| 4 | Reintento imposible | Orden copiar → estado → borrar |
| 5 | Enlace filtrado | URL corta por dueño |
| 6 | Cuarentena llena | Ciclo de vida + EXPIRADO |
