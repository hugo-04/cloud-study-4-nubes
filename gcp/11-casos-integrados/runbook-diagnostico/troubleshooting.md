# Google Cloud · Caso integrado · Runbook de diagnóstico · Troubleshooting

## Lista ordenada (los primeros 5 minutos)
1. **¿Es real?** Tasa de 5xx y volumen del LB en los últimos 5 min.
2. **¿Borde?** Denegaciones de Cloud Armor, certificados.
3. **¿Backends sanos?** Salud y latencia del backend.
4. **¿Cómputo?** Revisión activa de Cloud Run, instancias al tope, reinicios en GKE.
5. **¿Dependencias?** Conexiones de Cloud SQL, backlog/DLQ, APIs externas.
6. **¿Qué cambió?** Último despliegue y último apply.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| 502 en todo | Sin backends sanos | Revertir revisión / revisar probes |
| 504 | Backend lento | Escalar, revisar dependencias |
| 429/503 en Cloud Run | Instancias al máximo | Subir el tope o la concurrencia |
| 403 masivos | Cloud Armor | Revisar la regla reciente |
| Errores solo en un servicio | Dependencia | Pool, cuotas, latencias |
