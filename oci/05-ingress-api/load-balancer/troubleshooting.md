# Oracle OCI · Ingress y API · Load Balancer · Troubleshooting

## Lista ordenada
1. **¿Salud del backend set?** `oci lb backend-set-health get`: `OK`, `WARNING`, `CRITICAL`, `UNKNOWN`.
2. **¿El chequeo llega?** NSG/lista de seguridad del backend debe aceptar desde la subred del LB en el puerto del chequeo.
3. **¿El chequeo es correcto?** URL, puerto y código esperado (`200`); prueba con `curl` desde una VM en la subred del LB.
4. **¿Listener?** Puerto, protocolo, certificado vigente y backend set asociado.
5. **¿Reglas?** Una *routing policy* puede mandar a otro set.
6. **¿Tiempos?** `504` = backend lento; revisa `idle timeout` y tiempos de la app.
7. **¿Registros?** Activa los registros de acceso y error en Logging.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Todos los backends `CRITICAL` | NSG bloquea el chequeo o URL errónea | Regla desde la subred del LB; corrige URL |
| `502 Bad Gateway` | Backend cerró la conexión o no hay sanos | Salud y registros del backend |
| `504 Gateway Timeout` | Backend tarda más que el *timeout* | Optimiza o ajusta tiempos |
| Error de certificado | Vencido o cadena incompleta | Renueva; sube cadena completa |
| Sesión se pierde | Sin persistencia y estado en memoria | Estado fuera de la réplica |
| IP del cliente siempre igual | Lees la IP del socket | `X-Forwarded-For` |
