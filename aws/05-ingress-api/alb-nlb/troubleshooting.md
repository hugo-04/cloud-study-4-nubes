# AWS · ALB y NLB · Troubleshooting

Orden: **¿quién responde el error? (ALB o la app; cabecera `Server`/`X-Amzn-ErrorType`) → ¿destinos sanos? (`describe-target-health`) → ¿security groups → ¿health check (ruta, puerto, código)? → ¿timeouts/keep-alive? → ¿certificado/TLS? → logs de acceso**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| 502 Bad Gateway | La app cerró la conexión o devolvió respuesta inválida; keep-alive menor que el idle timeout | Logs de acceso (`elb_status_code` vs `target_status_code`) | Keep-alive de la app > idle timeout |
| 503 Service Unavailable | Sin destinos sanos en el target group | `describe-target-health` | Corregir health check/app; registrar destinos |
| 504 Gateway Timeout | La app tarda más que el idle timeout del ALB o no responde | `target_processing_time` en logs | Ajustar timeouts, optimizar |
| Destinos `unhealthy` | Health check mal (ruta/puerto/código) o SG bloquea al ALB | Motivo en `describe-target-health` | Ajustar `matcher`, puerto; SG de la tarea desde el SG del ALB |
| `Target.Timeout` / `FailedHealthChecks` | SG o NACL bloquean; la app no escucha | SG, NACL, `ss -ltn` | Abrir el puerto al SG del ALB |
| Certificado no válido en el navegador | Cert de otro dominio o sin SNI configurado; ACM pendiente de validación | ACM → estado | Validar por DNS; añadir cert al listener |
| `ERR_TOO_MANY_REDIRECTS` | La app redirige a HTTPS aunque ya viene por HTTPS (no lee `X-Forwarded-Proto`) | Cabeceras | `forward-headers-strategy`/`proxy-address-forwarding` |
| La app ve IP del ALB | No usa `X-Forwarded-For` | Logs de la app | Estrategia de cabeceras de reenvío |
| NLB: conexiones rechazadas | SG del destino no permite al cliente (con IP preservada) | Reglas del SG | Permitir origen real o rango del NLB |
| NLB: timeout con destinos de otra zona | Cross-zone desactivado y sin destinos en esa zona | Sanidad por zona | Activar cross-zone o registrar destinos |
| Despliegue corta peticiones | Deregistration delay muy bajo / app no hace graceful | Logs del ALB | Alinear delay, `stopTimeout` y apagado |
| Regla no coincide | Orden/prioridad de las reglas; host con puerto | Prioridades | Revisar condiciones; la de menor número gana |
| WebSocket se cae | Idle timeout | Logs | Subir idle timeout o enviar pings |
