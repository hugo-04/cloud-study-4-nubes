# Oracle OCI · Datos · PostgreSQL · Troubleshooting

## Lista ordenada
1. **¿Estado `ACTIVE`?** Mantenimiento o *failover* en curso.
2. **¿Red?** NSG 5432, DNS privado, endpoint correcto (primario vs lectura).
3. **¿TLS?** `sslmode` y certificado raíz del servicio.
4. **¿Autenticación?** Rol, contraseña (Vault), `pg_hba` administrado por el servicio.
5. **¿Conexiones?** `select count(*) from pg_stat_activity`.
6. **¿Lento?** `pg_stat_statements`, `EXPLAIN (ANALYZE, BUFFERS)`, bloqueos en `pg_locks`.
7. **¿Escritura falla con "read-only transaction"?** Estás en el endpoint de lectura.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `connection refused`/timeout | NSG o endpoint | Revisa red |
| `SSL error` | `sslmode`/certificado | Certificado del servicio |
| `password authentication failed` | Credenciales | Vault y rol |
| `too many connections` | Pools | Reduce pools |
| `cannot execute INSERT in a read-only transaction` | Endpoint de lectura | Usa el primario |
| Bloqueos largos | Migración o transacción abierta | `pg_locks`, `idle_in_transaction_session_timeout` |
