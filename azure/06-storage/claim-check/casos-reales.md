# Azure · Claim Check · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar.)

## Caso 1 · Archivos de 2 GB con Claim Check
- **Problema:** un proveedor enviaba catálogos enormes y el procesamiento fallaba por el tamaño del mensaje.
- **Solución:** subida por SAS, evento `BlobCreated`, ticket con URL, versión y hash a la cola, y un procesador que descarga por *streaming*.
- **Resultado:** procesamiento estable, reintentos seguros y la cola con mensajes de 1 KB.
- **Lección:** por la cola va **la referencia**, no el dato.

## Caso 2 · El ticket con SAS que caducó
- **Problema:** mensajes reintentados horas después fallaban con 403.
- **Causa:** el ticket llevaba una SAS de 15 minutos y la cola reintentaba hasta 1 hora.
- **Solución:** ticket **sin SAS**; el consumidor lee con identidad administrada (*Storage Blob Data Reader*).
- **Lección:** la credencial no debe viajar por la cola; si viaja, que dure más que los reintentos.

## Caso 3 · Procesamos el archivo equivocado
- **Problema:** un cliente reenvió un archivo con el mismo nombre; el consumidor procesó el contenido nuevo para el ticket viejo.
- **Causa:** el ticket apuntaba a la ruta sin versión.
- **Solución:** `blobVersionId` + `sha256` en el ticket; el consumidor lee esa versión y verifica el hash.
- **Lección:** referencia **inmutable** o verificación de integridad.

## Caso 4 · Duplicados que cobraron dos veces
- **Problema:** una factura se generó dos veces por un reintento del broker.
- **Solución:** detección de duplicados de Service Bus (10 min) + tabla de procesados con `mensajeId` único + operación idempotente.
- **Lección:** *at-least-once* es la norma; la idempotencia es del consumidor.

## Caso 5 · Blob inexistente y reintento infinito
- **Problema:** la cola tenía un mensaje que se reintentaba para siempre.
- **Causa:** el blob se había borrado por la regla de ciclo de vida antes de que el ticket se procesara.
- **Solución:** 404 → *dead-letter* con motivo `BLOB_AUSENTE`; ciclo de vida ajustado a ≥ retención del mensaje; alerta de DLQ.
- **Lección:** los ciclos de vida del blob y del mensaje deben coordinarse.

## Caso 6 · Blobs huérfanos
- **Problema:** miles de blobs sin ticket inflaban el costo.
- **Causa:** fallos de publicación después de subir; el cliente nunca confirmó.
- **Solución:** etiqueta `estado=sin-confirmar` al crear, regla de ciclo de vida que borra a los 2 días, y job de reconciliación.
- **Lección:** sin transacción blob+mensaje, la limpieza de huérfanos es parte del diseño.

## Caso 7 · El procesamiento más largo que el bloqueo
- **Problema:** archivos grandes se procesaban dos veces a la vez.
- **Causa:** el procesamiento duraba 12 min y el `lockDuration` era 5 min; el mensaje volvía a la cola.
- **Solución:** renovación automática del bloqueo (`maxAutoLockRenewDuration`) y `lockDuration` acorde.
- **Lección:** bloqueo ≥ tiempo de proceso o renovación activa.

## Caso 8 · Explosión de memoria
- **Problema:** el consumidor reventaba con `OutOfMemoryError` en archivos de 1,5 GB.
- **Solución:** *streaming* línea a línea con `openInputStream`, hash incremental y lotes pequeños en la BD.
- **Lección:** el streaming es un requisito, no una optimización.

## Caso 9 · Fan-out: un archivo, tres procesos
- **Problema:** el mismo catálogo debía indexarse, validarse y archivarse.
- **Solución:** tópico con tres suscripciones; cada consumidor lee el mismo blob con su identidad; el último en terminar marca `estado=procesado`.
- **Lección:** con Claim Check el fan-out no multiplica el dato en el broker.

## Caso 10 · Cumplimiento de datos personales
- **Problema:** los tickets quedaban en la DLQ semanas y contenían nombre y documento del cliente.
- **Solución:** el ticket solo tiene ids; los datos personales viven en el blob con retención controlada y cifrado con clave propia.
- **Lección:** minimiza lo que viaja por colas y logs.

## Caso 11 · Mismo patrón con Event Hubs (Kafka)
- **Problema:** un flujo de imágenes médicas de alto volumen no cabía en eventos de 1 MB.
- **Solución:** Event Hubs con registros-ticket (referencia + hash) y consumidores que leen el blob; reprocesar el histórico es releer el log.
- **Lección:** con streams, Claim Check mantiene los registros pequeños y el log barato.
