# Oracle OCI · Mensajería · Queue · Troubleshooting

## Lista ordenada
1. **¿Endpoint correcto?** `QueueClient` debe usar el `messages_endpoint` de la cola.
2. **¿Política?** `use queues` para producir/consumir.
3. **¿Red?** Puerta de servicios o NAT desde la subred privada.
4. **¿Los mensajes vuelven?** Visibilidad menor que el tiempo de proceso o el consumidor no borra.
5. **¿Crece la DLQ?** Revisa el contenido del primer mensaje muerto.
6. **¿Mensaje rechazado al enviar?** Tamaño máximo.
7. **¿Métricas?** Mensajes visibles, en vuelo y en DLQ (Monitoring).

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| 404 al enviar | Endpoint o OCID equivocados, o sin permiso | Endpoint de la cola; política |
| Duplicados | Visibilidad corta | Aumenta o extiende |
| Mensajes que no desaparecen | No se borra con el receipt | `DeleteMessage` al terminar |
| 400 al enviar | Mensaje grande | Claim check |
| DLQ creciente | Mensaje venenoso o bug | Analiza y reprocesa |
| Muchas solicitudes vacías | Sin long polling | `timeoutInSeconds` |
