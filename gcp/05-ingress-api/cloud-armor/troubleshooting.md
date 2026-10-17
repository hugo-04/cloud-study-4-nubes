# Google Cloud · Ingress y API · Cloud Armor · Troubleshooting

## Lista ordenada
1. **¿La política está adjunta al backend service correcto?**
2. **¿Qué regla coincidió?** Registros del balanceador: `jsonPayload.enforcedSecurityPolicy`.
3. **¿Vista previa?** `previewSecurityPolicy` muestra lo que haría.
4. **¿Prioridades?** Una regla `allow` anterior puede saltarse el WAF.
5. **¿IP del cliente correcta?** Detrás de otro proxy, usa la clave `XFF-IP` con cuidado.
6. **¿El tráfico pasa por el balanceador?**

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| 403 legítimos | Falso positivo | Exclusión o sensibilidad menor |
| Nada se bloquea | Vista previa o regla allow antes | Revisa prioridades |
| 429 a muchos usuarios | NAT compartida | Clave distinta o umbral mayor |
| Ataques en el backend | Bypass | Ingress/firewall |
| Cambios sin efecto | Propagación | Espera unos minutos |
