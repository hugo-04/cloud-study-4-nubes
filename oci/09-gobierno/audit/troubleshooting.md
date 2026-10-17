# Oracle OCI · Gobierno · Audit · Troubleshooting

## Lista ordenada
1. **¿Región correcta?** Los eventos están en la región donde ocurrió la llamada; IAM en la región *home*.
2. **¿Compartimento correcto?** El evento se registra en el compartimento del recurso.
3. **¿Ventana de tiempo?** `startTime`/`endTime` en UTC.
4. **¿Permiso?** `read audit-events`.
5. **¿Paginación?** Muchas páginas en ventanas grandes; acota.
6. **¿El conector copia?** Estado del Service Connector y permisos al bucket.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| No aparece el evento IAM | Región equivocada | Consulta la región *home* |
| Consulta lenta o incompleta | Ventana muy grande | Acota por tiempo/compartimento |
| 404 | Sin `read audit-events` | Política |
| Bucket de archivo vacío | Conector sin permisos | Política de servicio |
| Eventos de más de 365 días | Fuera de retención | Solo en tu copia |
