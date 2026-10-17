# Oracle OCI · Datos · OCI Cache · Troubleshooting

## Lista ordenada
1. **¿Clúster `ACTIVE`?**
2. **¿Red?** NSG 6379 desde la app; FQDN privado resuelve.
3. **¿TLS?** El cliente debe usar `rediss://` (TLS).
4. **¿Usuario/contraseña?** ACL del usuario y permisos de comandos y prefijos.
5. **¿Modo clúster?** En modo *sharded*, el cliente debe soportar clúster y usar el endpoint de descubrimiento.
6. **¿Memoria llena?** Métricas de memoria y expulsiones.
7. **¿Latencia?** Comandos lentos (`SLOWLOG`) o claves enormes.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Timeout al conectar | NSG o sin TLS | Abre 6379; usa `rediss://` |
| `NOAUTH`/`WRONGPASS` | Credenciales | Usuario y Vault |
| `MOVED` | Modo clúster con cliente simple | Cliente en modo clúster |
| Aciertos bajos | TTL corto o expulsiones | Revisa memoria y TTL |
| Picos de latencia | Claves grandes o comandos O(n) | Divide claves; evita `KEYS` |
