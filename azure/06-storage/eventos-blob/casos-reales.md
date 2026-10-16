# Azure · Eventos de Blob · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar.)

## Caso 1 · Procesar catálogos al llegar, sin sondear
- **Problema:** un job cada 5 minutos listaba el contenedor de proveedores; con 400 000 blobs tardaba más que el intervalo.
- **Solución:** suscripción `BlobCreated` → cola de Service Bus, con filtro por prefijo `proveedores/entrada/`; el procesador lee el blob con `If-Match: eTag`.
- **Resultado:** latencia de minutos a segundos y se eliminó el listado.
- **Lección:** el listado crece con el contenedor; el evento no.

## Caso 2 · El bucle infinito de miniaturas
- **Problema:** la factura de Functions se multiplicó por 40 en un fin de semana.
- **Causa:** la Function generaba la miniatura y la guardaba en el **mismo contenedor**, lo que disparaba otro `BlobCreated`, que generaba otra miniatura…
- **Solución:** contenedores separados (`originales` y `miniaturas`) y filtro por contenedor y por prefijo.
- **Lección:** entrada y salida nunca comparten ruta bajo la misma suscripción.

## Caso 3 · Duplicados y la factura emitida dos veces
- **Problema:** una factura se generó dos veces al reintentar Event Grid.
- **Causa:** el handler tardó más que el tiempo de espera, Event Grid reintentó y ambos terminaron.
- **Solución:** idempotencia con el `id` del evento en una tabla con clave única; el webhook solo encola y responde 200.
- **Lección:** entrega **al menos una vez** = consumidor idempotente.

## Caso 4 · Eventos desordenados
- **Problema:** un blob sobrescrito dos veces seguidas dejó en el índice la versión **vieja**.
- **Causa:** llegó primero el evento de la segunda escritura y después el de la primera.
- **Solución:** guardar el `sequencer` procesado por blob y descartar eventos con `sequencer` menor; leer con `If-Match`.
- **Lección:** el orden no está garantizado; el `sequencer` ordena por blob.

## Caso 5 · Webhook que nunca se validaba
- **Problema:** la suscripción fallaba al crearse con "validation handshake failed".
- **Causa:** el endpoint exigía autenticación y rechazaba la petición de validación (401).
- **Solución:** aceptar la validación en una ruta con la autenticación de Event Grid (token de Entra ID de la aplicación) y responder `validationResponse`.
- **Lección:** el handshake ocurre **al crear** la suscripción y debe responder rápido.

## Caso 6 · Cero eventos y un filtro mal escrito
- **Problema:** no llegaba nada a la cola.
- **Causa:** el filtro decía `/blobServices/default/containers/Subidas/…` (mayúscula) y el contenedor es `subidas`; el filtro distingue mayúsculas.
- **Solución:** corregir el prefijo y probar con un evento de ejemplo; métrica *Matched Events* para comprobar.
- **Lección:** si *Matched Events* es 0, el problema es el filtro, no la entrega.

## Caso 7 · Dead-letter que salvó una migración
- **Problema:** durante una caída de 6 horas del consumidor se perdieron avisos.
- **Solución:** reintentos largos + dead-letter en un contenedor; después de arreglar el consumidor se reprocesaron los eventos del contenedor.
- **Lección:** configura dead-letter **antes** del incidente; por defecto los eventos expirados se descartan.

## Caso 8 · Entrega a una cola con red privada
- **Problema:** Event Grid no podía entregar a un Service Bus detrás de Private Endpoint.
- **Solución:** Service Bus Premium con Private Endpoint, excepción de "servicios de confianza", identidad administrada del tópico con *Azure Service Bus Data Sender*.
- **Lección:** con red privada se entrega con **identidad** y el destino debe admitir servicios de confianza.

## Caso 9 · Archivos subidos por SFTP
- **Problema:** los archivos de un socio por SFTP no se procesaban.
- **Causa:** el filtro `api` solo admitía `PutBlob`/`PutBlockList`; por SFTP la operación es `SftpCommit`.
- **Solución:** ampliar el filtro avanzado de `data.api` o quitarlo y filtrar por prefijo.
- **Lección:** el origen de la subida cambia el valor de `api`.

## Caso 10 · Auditoría que no podía perder nada
- **Problema:** el área legal pidió probar que ningún borrado quedó sin registrar.
- **Solución:** habilitar **change feed** (registro ordenado y durable) además de los eventos para reaccionar rápido.
- **Lección:** eventos = reaccionar; change feed = registro fiable.

## Caso 11 · Lifecycle que borra y dispara avisos
- **Problema:** miles de eventos `BlobDeleted` saturaron la cola cada madrugada.
- **Causa:** la política de ciclo de vida borraba blobs viejos y el consumidor los procesaba como borrados de usuario.
- **Solución:** suscripción distinta para borrados con filtro por prefijo y distinguir `data.api`; escalar el consumidor o ignorar lo que no importa.
- **Lección:** el sistema también borra: no todo `BlobDeleted` es una acción de usuario.
