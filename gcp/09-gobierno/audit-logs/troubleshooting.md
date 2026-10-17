# Google Cloud · Gobierno · Cloud Audit Logs · Troubleshooting

## Lista ordenada
1. **¿Tipo correcto?** `logName` termina en `cloudaudit.googleapis.com%2Factivity`, `data_access`, `system_event` o `policy`.
2. **¿Data Access activo?** `auditConfigs` del proyecto/carpeta/organización.
3. **¿Permiso para verlos?** Data Access requiere `privateLogViewer`.
4. **¿El sink exporta?** Errores del sink y permisos de su cuenta en el destino.
5. **¿Retención?** ¿Se pasó del periodo del bucket?

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| No hay entradas de lectura | Data Access desactivado | Actívalo |
| Ves Admin Activity pero no Data Access | Falta `privateLogViewer` | Rol |
| El sink no escribe | Cuenta sin permiso | Da el rol que indica el sink |
| Costo alto | Data Access amplio | Selectivo o exenciones |
| Entrada sin principal | Llamada de Google o anónima | Revisa `System Event` y acceso público |
