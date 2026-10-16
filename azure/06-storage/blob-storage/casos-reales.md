# Azure · Blob Storage · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar.)

## Caso 1 · Logs que cuestan una fortuna
- **Problema:** 3 TB de logs en el tier caliente, creciendo cada mes.
- **Solución:** regla de ciclo de vida: Cool a los 30 días, Archive a los 180, borrado a los 2 años; versiones antiguas a 30 días.
- **Resultado:** el costo bajó de forma notable sin perder trazabilidad.
- **Lección:** el ciclo de vida es el mayor ahorro del servicio; configúralo el primer día.

## Caso 2 · Borrado accidental de un contenedor
- **Problema:** un script de limpieza eliminó el contenedor `catalogo` en producción.
- **Solución:** *soft delete de contenedores* (14 días) lo recuperó en minutos; después se añadió bloqueo de recurso y un rol de datos sin permiso de borrar contenedores.
- **Lección:** soft delete + versionado son baratos comparados con perder datos.

## Caso 3 · El pico de `503 ServerBusy`
- **Problema:** una carga nocturna de 40 millones de archivos pequeños fallaba con `503`.
- **Causa:** nombres con prefijo secuencial por fecha-hora; una sola partición recibía todo; sin reintentos con espera.
- **Solución:** prefijo con hash corto (`a3/2026-10-16T...`), concurrencia moderada, `RequestRetryOptions` exponenciales y AzCopy.
- **Lección:** el servicio reparte por rango de nombres y limita por cuenta; reintenta con *backoff* y reparte la carga.

## Caso 4 · Dos escritores, un archivo
- **Problema:** dos instancias del servicio de catálogo reemplazaban `catalogo.json` y a veces se perdían cambios.
- **Solución:** escritura condicional con `If-Match: <ETag>`; ante `412 Precondition Failed`, releer, fusionar y reintentar.
- **Lección:** la concurrencia optimista con ETag evita sobrescrituras silenciosas; los *leases* son para exclusión mutua corta.

## Caso 5 · Cuenta abierta con datos de clientes
- **Problema:** un hallazgo de seguridad: un contenedor con acceso anónimo contenía exportaciones.
- **Solución:** `allowBlobPublicAccess=false` en la cuenta, política de Azure que lo exige, Private Endpoint y `allowSharedKeyAccess=false`.
- **Lección:** el control de "público" va a nivel de **cuenta** y se impone con políticas.

## Caso 6 · Rehidratación que tardó todo el día
- **Problema:** una auditoría pidió documentos de 2022, que estaban en Archive.
- **Solución:** rehidratación con prioridad alta para los pocos blobs críticos y estándar para el resto; coordinación con el plazo.
- **Lección:** Archive es offline; planifica la recuperación y no lo uses para datos que podrías necesitar de inmediato.

## Caso 7 · Cargo por borrado anticipado
- **Problema:** un proceso movía blobs a Cool y los borraba a los 10 días; la factura mostró cargos de permanencia mínima.
- **Solución:** mantener en Hot hasta el borrado o ajustar la retención a ≥ 30 días.
- **Lección:** Cool/Cold/Archive tienen permanencia mínima; el ahorro depende del patrón de acceso.

## Caso 8 · Descargas que reventaron la memoria
- **Problema:** una API cargaba blobs de 800 MB con `downloadContent()`; `OutOfMemoryError` en AKS.
- **Solución:** *streaming* (`openInputStream` / `downloadToFile` / `Flux<ByteBuffer>`) y redirección a una SAS de lectura para archivos grandes.
- **Lección:** nunca cargues archivos grandes completos en memoria.

## Caso 9 · Ransomware de laboratorio
- **Problema:** una credencial comprometida borró y sobrescribió datos.
- **Solución:** versionado + soft delete + **inmutabilidad** (retención) para el contenedor de respaldos; claves compartidas deshabilitadas.
- **Lección:** la inmutabilidad (WORM) es la última línea de defensa.

## Caso 10 · Sitio estático para la campaña
- **Problema:** una landing page promocional necesitaba picos grandes y costo mínimo.
- **Solución:** sitio estático en `$web` con Front Door, caché y dominio propio.
- **Lección:** para contenido estático, Blob + CDN es barato y escala solo.

## Caso 11 · Replicación entre regiones para lectura cercana
- **Problema:** equipos en Brasil leían imágenes desde Estados Unidos con latencia alta.
- **Solución:** replicación de objetos hacia una cuenta en Brasil y lectura local; cambios en el origen se propagan de forma asíncrona.
- **Lección:** la replicación de objetos acerca datos de solo lectura; recuerda que es asíncrona.
