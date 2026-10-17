# Oracle OCI · Gobierno · Presupuestos y costos · Troubleshooting

## Lista ordenada
1. **¿Presupuesto en la raíz?** Los presupuestos se crean en el compartimento raíz (tenancy) apuntando al objetivo *(verifica)*.
2. **¿Objetivo correcto?** Compartimento o etiqueta de costo activada.
3. **¿Retraso de datos?** Los costos de hoy aparecen horas después.
4. **¿Alerta no llegó?** Destinatarios, tema y umbral; las alertas se evalúan periódicamente.
5. **¿Usage API vacía?** Ventana en UTC y alineada al día; `tenantId` correcto.
6. **¿Montos distintos a la factura?** Descuentos, créditos e impuestos.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Presupuesto en 0 | Objetivo equivocado | Revisa compartimento/etiqueta |
| Etiqueta no filtra | No es de costo | Actívala como de costo |
| Usage API error 400 | Fechas no alineadas | Usa medianoche UTC |
| Alerta no llega | Correo/tema | Verifica destinatarios |
| Diferencia con factura | Créditos/impuestos | Compara con el mismo tipo de consulta |
