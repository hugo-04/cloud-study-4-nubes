# Azure · Caso integrado · Subida con Claim Check · Troubleshooting

Orden: **¿la app obtuvo la SAS? → ¿el `PUT` llegó a Blob? → ¿se generó el evento? → ¿lo leyó el validador? → ¿qué estado tiene la fila?** Consultas en [`kql-subidas.md`](ejemplos/kql/kql-subidas.md) y el script [`inspeccionar-subidas.sh`](ejemplos/cli/inspeccionar-subidas.sh).

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `403 AuthenticationFailed` al subir | SAS vencida, reloj desfasado o URL alterada | Hora del dispositivo; parámetros `se`/`st` de la URL | Pedir otra SAS; no modificar la URL; margen de reloj |
| `403 AuthorizationPermissionMismatch` | Falta el permiso `create`/`write` o la ruta no coincide | Permisos (`sp`) y ruta firmados | Firmar con `create`+`write` sobre la ruta exacta |
| El navegador falla en `OPTIONS` | CORS de la cuenta incompleto | Pestaña de red del navegador, respuesta del preflight | Añadir el origen, `PUT`, `OPTIONS` y cabeceras `x-ms-*` |
| `409`/`BlobAlreadyExists` | Se reintentó una SAS de solo `create` | Código de error | Permitir `write` o pedir una SAS nueva |
| `400` tipo de blob | Falta `x-ms-blob-type: BlockBlob` | Cabeceras de la petición | Enviar las `cabeceras` que devolvió la API |
| La subida existe, la fila sigue `PENDIENTE` | El evento no llegó a la cola | Suscripción de Event Grid (estado y filtro) y mensajes en la cola | Revisar el filtro `subject_begins_with` y el rol *Queue Message Sender* de la identidad del tópico |
| La cola crece | El validador no consume o falla | Logs del validador; permisos *Queue Message Processor* | Corregir permisos/DNS; revisar el tiempo de invisibilidad |
| Mensajes que reaparecen sin parar | Excepción en la validación | Logs de `subidas.validador` | Corregir causa; mover a una cola de fallidos tras N intentos |
| Todo se rechaza con `tipo_no_coincide` | El cliente declara un tipo distinto del real (p. ej. `jpg` vs `jpeg`) | Tipo declarado vs bytes | Normalizar tipos en la API |
| Rechazo `tipo_no_permitido` en un PDF válido | PDF con bytes antes de `%PDF-` | Primeros bytes | Ampliar la lectura de cabecera (la especificación tolera algunos bytes previos) |
| Copia a `validados` falla con 403 | La identidad no puede leer el origen | Rol en `cuarentena` | Dar datos en ambos contenedores; verificar la autorización del origen en la copia |
| Fila `SUBIDA` eterna | El validador murió; el conciliador no corre | Hora de `actualizada_en` y logs del conciliador | Activar el conciliador; revisar el plazo |
| Cuarentena no se limpia | La política tiene otro prefijo o está deshabilitada | `az storage account management-policy show` | Corregir `prefix_match` (`cuarentena/`) |
| Eventos de otros contenedores en la cola | Filtro ausente | Suscripción | `subject_begins_with` con el contenedor |
| `terraform apply`: no se puede crear la suscripción de eventos | Falta el rol de la identidad del tópico sobre la cola | Orden de creación | `depends_on` del rol y reintentar |
