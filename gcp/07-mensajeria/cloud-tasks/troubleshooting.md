# Google Cloud · Mensajería · Cloud Tasks · Troubleshooting

## Lista ordenada
1. **¿La tarea se creó?** `ALREADY_EXISTS` = deduplicación (esperado).
2. **¿Cola pausada o con tasa baja?**
3. **¿El destino responde 2xx?** Registros de Cloud Tasks y del destino.
4. **¿OIDC?** Cuenta, audiencia (URL del servicio) y `run.invoker`.
5. **¿El productor puede usar la SA?** `iam.serviceAccountUser` sobre la SA de despacho.
6. **¿Plazo de entrega?** Destino lento.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `ALREADY_EXISTS` | Nombre repetido | Ignóralo (idempotente) |
| `PERMISSION_DENIED` al crear | Falta enqueuer/actAs | Roles |
| 401/403 en el destino | OIDC/invoker | Configura |
| Reintentos constantes | Destino falla | Corrige o 2xx en permanentes |
| Tareas atrasadas | Tasa baja | Ajusta la cola |
