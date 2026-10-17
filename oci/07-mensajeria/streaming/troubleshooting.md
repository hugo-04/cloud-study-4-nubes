# Oracle OCI · Mensajería · Streaming · Troubleshooting

## Lista ordenada
1. **¿Endpoint correcto?** `StreamClient` usa el endpoint de mensajes del pool; Kafka usa el `bootstrap` del pool.
2. **¿Política?** `use stream-push` / `use stream-pull`.
3. **¿Red?** Pool privado: el cliente debe estar en la VCN con DNS privado.
4. **¿Kafka no autentica?** Usuario `<tenancy>/<usuario>/<ocid pool>` y *auth token* vigente; SASL_SSL PLAIN.
5. **¿Throttling (429)?** Partición caliente o capacidad insuficiente.
6. **¿Fallos parciales?** Revisa `failures` y `entries[].error`.
7. **¿Lag creciente?** Consumidores lentos o pocos.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| 404 al publicar | Endpoint/OCID o permiso | Endpoint del pool; política |
| `SaslAuthenticationException` | Usuario o token | Formato del usuario; token nuevo |
| 429 | Partición saturada | Clave / más particiones |
| Mensajes ausentes | Fallos parciales ignorados | Reintenta los fallidos |
| Consumidor no lee nada | Cursor `LATEST` sin tráfico nuevo | Cursor de grupo o `TRIM_HORIZON` |
| Rebalanceos constantes | Procesamiento lento por lote | Lotes más pequeños, *timeouts* |
