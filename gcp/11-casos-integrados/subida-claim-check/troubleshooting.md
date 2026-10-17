# Google Cloud · Caso integrado · Subida con claim check · Troubleshooting

## Lista ordenada
1. **¿La URL funciona?** 403 `SignatureDoesNotMatch` = método, tipo o cabeceras distintas a las firmadas.
2. **¿Llegó el objeto?** `gcloud storage ls gs://.../cuarentena/`.
3. **¿Salió la notificación?** Backlog de `subidas-llegadas`.
4. **¿El validador recibió?** Logs del push y respuesta 2xx.
5. **¿Precondición fallida?** 412: el objeto cambió; el evento nuevo lo reprocesará.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `SignatureDoesNotMatch` | Content-Type distinto | Envía el mismo tipo firmado |
| Sin eventos | Permiso del agente de Storage al tema | `pubsub.publisher` al agente |
| `412 Precondition Failed` | Generación cambió | Ignora; llega otro evento |
| Rechazos inesperados | Firma no contemplada | Revisa tipos permitidos |
| Cuarentena crece | Ciclo de vida | Revisa la regla |
