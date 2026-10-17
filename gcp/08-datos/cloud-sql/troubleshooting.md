# Google Cloud · Datos · Cloud SQL · Troubleshooting

## Lista ordenada
1. **¿Connection name correcto?** `proyecto:región:instancia`.
2. **Red:** con IP privada, ¿PSA configurado y la app en esa VPC (o con conector VPC/egreso directo)?
3. **IAM:** `cloudsql.client` + `cloudsql.instanceUser`; ¿el usuario IAM existe en la instancia?
4. **Usuario de base:** el email de la SA sin `.gserviceaccount.com` (PostgreSQL).
5. **Permisos SQL:** `GRANT` sobre el esquema y tablas.
6. **Conexiones:** total de pools vs `max_connections`.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `FATAL: Cloud SQL IAM user authentication failed` | Usuario o rol | Crea el usuario IAM y da `instanceUser` |
| Timeout | Red | PSA, VPC, egreso |
| `permission denied for table` | GRANT | Concede en la base |
| `too many connections` | Pools | Reduce pool o usa réplicas |
| Lentitud | Consultas | Query Insights e índices |
