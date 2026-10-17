# Oracle OCI · Caso integrado · Tienda online · Troubleshooting

## Lista ordenada (de afuera hacia adentro)
1. **¿Entra el tráfico?** WAF (bloqueos), LB (salud de backends), Ingress (reglas).
2. **¿El pod responde?** Readiness, registros, conexiones a ATP.
3. **¿Se escribe el outbox?** Filas nuevas por pedido.
4. **¿El relay publica?** Filas `PENDIENTE` envejeciendo = relay caído o fallando.
5. **¿La cola crece?** Consumidores lentos o caídos; DLQ.
6. **¿El inbox rechaza todo?** Clave mal calculada (todos parecen duplicados).

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| 502 en checkout | Backends no sanos | Salud del LB y readiness |
| Pedido creado sin factura | Relay detenido | Estado del relay y outbox |
| Facturas duplicadas | Inbox ausente | Clave única por evento |
| DLQ creciendo | Evento inválido | Revisar contrato y datos |
| Outbox con muchos `FALLIDO` | Error permanente al publicar | Permisos o tamaño de mensaje |
