# AWS · Caso integrado · Subida con Claim Check · Troubleshooting

## Lista ordenada
1. **¿La API entregó la URL?** Revisa que exista la carga `PENDIENTE` en `prod-cargas`.
2. **¿El PUT respondió 200?** Un `403` casi siempre es firma: tipo, tamaño, URL vencida o reloj del cliente.
3. **¿Existe el objeto en `entrada/{id}`?** `aws s3api head-object`.
4. **¿Llegó el evento?** Métricas de la regla (`MatchedEvents`, `FailedInvocations`) y mensajes en la cola `prod-validacion`.
5. **¿El validador lo recibió?** Logs del servicio; permisos de lectura sobre `entrada/*`.
6. **¿Qué estado tiene?** `RECHAZADO` trae el motivo en `detalle`.
7. **¿Cayó a la DLQ?** Mensaje ilegible o error persistente.

## Síntoma → causa
| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `403 SignatureDoesNotMatch` | Tipo o tamaño distinto del firmado | Usar el `contentType` de la respuesta; subir exactamente `bytes` |
| `403 Request has expired` | Pasaron más de 5 minutos | Pedir otra URL |
| Falla CORS en el navegador | Origen o cabeceras no permitidos | Revisar `aws_s3_bucket_cors_configuration` (PUT, `content-type`, `content-length`) |
| Quedó `PENDIENTE` con objeto en S3 | Regla desactivada o sin permiso de cola | Reconciliador lo revalida; arreglar la regla |
| `RECHAZADO` por `FIRMA_NO_COINCIDE` | Archivo de otro formato | Es correcto; informar al usuario |
| `RECHAZADO` por `TAMANO_DISTINTO` | El cliente envió otro tamaño | Alinear front y API |
| Mensajes en DLQ | Evento mal formado o error persistente | Leer, corregir, `start-message-move-task` |
| Cuarentena crece | Faltan reglas de ciclo de vida | Aplicar la regla de 1 día |
