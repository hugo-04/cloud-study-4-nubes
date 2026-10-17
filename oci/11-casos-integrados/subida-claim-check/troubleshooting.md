# Oracle OCI · Caso integrado · Subida con claim check · Troubleshooting

## Lista ordenada
1. **¿La PAR funciona?** Vencimiento, nombre exacto, método `PUT`.
2. **¿Llegó a cuarentena?** `oci os object head` del nombre esperado.
3. **¿Se disparó el evento?** Eventos del bucket activos y regla habilitada.
4. **¿Corrió la función?** Registros de la aplicación de funciones.
5. **¿Se movió?** `renameObject` falla si el ETag cambió o el destino existe.
6. **¿Llegó el ticket a la cola?**
7. **¿El reconciliador corre?**

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| 404 al subir | PAR vencida/nombre distinto | Nueva PAR |
| Queda `RECIBIDA` | Función sin permisos o caída | Registros y políticas |
| `RECHAZADA` legítima | Firma no contemplada (por ejemplo, HEIC) | Ajusta tipos permitidos |
| Error 409/412 al renombrar | Destino existe o ETag distinto | Revisa idempotencia |
| Cuarentena llena | Validador detenido | Revisa función y ciclo de vida |
