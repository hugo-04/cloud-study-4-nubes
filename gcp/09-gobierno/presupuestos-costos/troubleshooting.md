# Google Cloud · Gobierno · Presupuestos y costos · Troubleshooting

## Lista ordenada
1. **¿El presupuesto filtra lo que crees?** Proyectos, servicios, labels, créditos incluidos o no.
2. **¿Llega el mensaje a Pub/Sub?** Permiso del servicio de facturación sobre el tema.
3. **¿La exportación existe?** Dataset y tablas `gcp_billing_export_*`; tiene retraso.
4. **¿Costo bruto o neto?** Suma los `credits`.
5. **¿Moneda y periodo?** `currency` e `invoice.month`.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| No llegan avisos | Umbrales o destinatarios | Revisa reglas y canales |
| No llega a Pub/Sub | Permisos del tema | Da `pubsub.publisher` a la cuenta de facturación *(verifica)* |
| Cifras distintas a la factura | Créditos o impuestos | Usa costo neto e `invoice.month` |
| Tabla vacía | Exportación reciente | Espera; no es retroactiva |
| Mensajes repetidos | Se envían varias veces al día | Reacciona solo al cambio de umbral |
