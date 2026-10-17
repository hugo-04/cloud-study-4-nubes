# Google Cloud · Compute · Cloud Run functions · Troubleshooting

## Lista ordenada
1. **¿Compiló?** Registros de Cloud Build del despliegue.
2. **¿Arranca?** Clase/método de entrada correctos.
3. **¿Llega el evento?** Disparador de Eventarc, filtros y SA del disparador con `run.invoker`.
4. **¿Falla la función?** Registros; con reintentos verás reintentos.
5. **¿Permisos de la función?** SA propia y roles.
6. **¿Tiempo máximo?** Para eventos, el límite es menor.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Despliegue falla | Error de compilación o dependencia | Revisa el build |
| No se invoca | Disparador sin permiso | `run.invoker` a la SA del disparador |
| Ejecuciones repetidas | Reintentos por error | Corrige y hazla idempotente |
| 403 al llamar HTTP | Sin invoker o sin ID token | Rol y token |
| Timeout | Trabajo largo | Cloud Run jobs |
