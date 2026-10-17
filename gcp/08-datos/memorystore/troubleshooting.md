# Google Cloud · Datos · Memorystore · Troubleshooting

## Lista ordenada
1. **Red:** ¿la app está en la VPC (o con egreso directo/conector)? ¿PSC o PSA correcto?
2. **TLS:** si está activo, el cliente debe usar `rediss://` y confiar en la CA del servicio.
3. **Autenticación:** token IAM o cadena AUTH vigente.
4. **Memoria y expulsiones:** métricas de uso y `evicted_keys`.
5. **Latencia:** comandos lentos (`SLOWLOG`), claves grandes.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Timeout al conectar | Red | VPC, PSC, firewall |
| `NOAUTH` / `WRONGPASS` | Autenticación | Token o AUTH |
| Error TLS | CA | Usa la CA del servicio |
| `OOM command not allowed` | Memoria | TTL, LRU, más capacidad |
| `MOVED` | Modo clúster | Cliente en modo clúster |
