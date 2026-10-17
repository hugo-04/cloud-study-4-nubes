# Google Cloud · IAM · Roles y políticas · Troubleshooting

## Lista ordenada
1. **¿Qué principal hace la llamada?** En la app, la cuenta de servicio efectiva (ADC).
2. **¿Qué permiso falta?** El error 403 lo nombra (`storage.objects.get`).
3. **Policy Troubleshooter** con principal, permiso y recurso.
4. **¿Denegación?** Una política de denegación puede ganarle a un rol.
5. **¿Condición falsa?** Fecha vencida o recurso fuera del patrón.
6. **¿Propagación?** Los cambios tardan segundos o minutos *(verifica)*.
7. **¿API habilitada?** Un 403 de «API no habilitada» no es IAM.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `403 PERMISSION_DENIED` | Falta el rol | Troubleshooter y rol mínimo |
| 403 tras otorgar el rol | Propagación o condición | Espera / revisa condición |
| 403 con rol correcto | Política de denegación | Revisa denegaciones |
| `SERVICE_DISABLED` | API apagada | Habilítala |
| Cambio de IAM rechazado | ETag desactualizado | Relee y reintenta |
