# Oracle OCI · Ingress y API · Ingress en OKE · Troubleshooting

## Lista ordenada
1. **¿Se creó el LB?** `kubectl describe svc|ingress`: los eventos dicen si el controlador falló (permisos, cuota, subred).
2. **¿IP asignada?** `EXTERNAL-IP` en `<pending>` = el LB no se pudo crear.
3. **¿Backends sanos?** Salud del backend set en OCI; con NodePort, el NSG de nodos debe aceptar desde el LB.
4. **¿Reglas del Ingress?** Host, ruta y `pathType`; `ingressClassName` correcto.
5. **¿Pods listos?** `readinessProbe` y endpoints del Service.
6. **¿TLS?** Secreto del certificado en el mismo namespace.
7. **¿Anotaciones válidas?** Un error de nombre se ignora en silencio.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `EXTERNAL-IP <pending>` | Permisos o cuota de LB | Eventos del Service; política; límites |
| 502 desde el LB | Backends no sanos | NSG nodos/pods; *readiness* |
| 404 del Ingress | Host o ruta no coinciden | Revisa reglas e IngressClass |
| Certificado por defecto | Secreto TLS mal referenciado | `tls.secretName` y namespace |
| IP cambió | IP no reservada | Reserva y anota |
