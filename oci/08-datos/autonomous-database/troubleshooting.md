# Oracle OCI · Datos · Autonomous Database · Troubleshooting

## Lista ordenada
1. **¿Estado `AVAILABLE`?** Una base detenida o en mantenimiento no acepta conexiones.
2. **¿Red?** Endpoint privado: DNS privado resuelve el host; NSG permite 1522 desde la app.
3. **¿TLS?** Si `isMtlsConnectionRequired = true`, necesitas wallet; si no, usa el perfil TLS one-way.
4. **¿Usuario y contraseña?** Cuenta bloqueada o contraseña expirada.
5. **¿Sesiones?** Límite del servicio elegido; tamaño de los pools × réplicas.
6. **¿Lentitud?** Performance Hub: SQL top, esperas, planes.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `ORA-12506` / no conecta | Lista de acceso o red | ACL / NSG / DNS |
| `ORA-29024` / TLS | Wallet o perfil equivocado | Perfil correcto |
| `ORA-01017` | Credenciales | Revisa usuario y Vault |
| `ORA-00018` sesiones | Pools grandes o servicio `high` | `tp` y pools acotados |
| Lento en horas punta | Consultas sin índice | Performance Hub |
