# Google Cloud · Compute · Cloud Run · Troubleshooting

## Lista ordenada
1. **¿La revisión arranca?** «Container failed to start»: el proceso debe escuchar en `$PORT` (8080) a tiempo.
2. **¿403 al llamar?** Falta `run.invoker` o el ID token tiene otra audiencia.
3. **¿404?** Ingress interno y llamada desde fuera, o URL de otra región.
4. **¿Latencia alta?** Arranques en frío; mínimo de instancias; concurrencia.
5. **¿429/503?** Máximo de instancias alcanzado o sin capacidad.
6. **¿No llega a la base/VPC?** Direct VPC egress o conector; firewall.
7. **¿Registros?** Cloud Logging por servicio y revisión.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Revisión falla al arrancar | No escucha en `$PORT` o arranque lento | Puerto y startup probe |
| 403 | Invoker o audiencia | Rol y audiencia = URL del servicio |
| 429 | Máximo de instancias | Sube máximo o concurrencia |
| Timeout a la base | Sin salida a la VPC | VPC egress |
| Trabajo de fondo no corre | CPU solo en peticiones | Cambia el modelo |
