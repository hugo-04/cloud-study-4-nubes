# Google Cloud · Mensajería · Eventarc · Troubleshooting

## Lista ordenada
1. **¿El disparador está activo?** Condiciones del disparador.
2. **¿El evento existe?** Para Audit Logs, busca la entrada en Logging; ¿están activos esos registros?
3. **¿Filtros correctos?** Valores exactos de `serviceName` y `methodName`.
4. **¿La SA del disparador puede invocar?** `run.invoker` y `eventarc.eventReceiver`.
5. **¿El destino responde 2xx?** Registros del servicio.
6. **¿Región?** Algunos disparadores deben estar en la región del recurso o `global`.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Nunca llega | Registro inexistente | Activa Audit Logs |
| 403 en el destino | Invoker | Rol a la SA |
| Reintentos | Destino falla | Responde 2xx a lo decidido |
| Duplicados | Al menos una vez | Dedupe |
| Error al crear | Región/filtros | Revisa ubicación y atributos |
