# Oracle OCI · Datos · MySQL HeatWave · Troubleshooting

## Lista ordenada
1. **¿Estado `ACTIVE`?** Respaldo, mantenimiento o *failover* en curso.
2. **¿Red?** Endpoint privado, NSG 3306, DNS de la subred.
3. **¿TLS?** Modo SSL del cliente compatible con el servidor.
4. **¿Conexiones?** `SHOW STATUS LIKE 'Threads_connected'` vs `max_connections`.
5. **¿Consulta lenta?** `EXPLAIN`; ¿se descarga a HeatWave? (`EXPLAIN` muestra el uso del motor secundario).
6. **¿Réplicas?** Retraso de replicación en métricas.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `Communications link failure` | Red o *failover* | NSG / reconexión del pool |
| `Too many connections` | Suma de pools | Reparte `max_connections` |
| `Access denied` | Usuario/host/contraseña | `GRANT` y Vault |
| Consulta no usa HeatWave | Tablas no cargadas o consulta no elegible | Carga las tablas; revisa `EXPLAIN` |
| Datos viejos en lecturas | Retraso de réplica | Lee del primario |
