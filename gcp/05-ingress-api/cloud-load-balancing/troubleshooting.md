# Google Cloud · Ingress y API · Cloud Load Balancing · Troubleshooting

## Lista ordenada
1. **¿DNS a la IP del balanceador?**
2. **¿Certificado `ACTIVE`?** Los administrados tardan en emitirse; el DNS debe apuntar antes.
3. **¿URL map?** `gcloud compute url-maps validate` o pruebas del mapa.
4. **¿Salud de backends?** `gcloud compute backend-services get-health`.
5. **¿Firewall desde rangos de Google?**
6. **¿Timeouts?** Del backend service vs de la app.
7. **¿Cloud Armor bloqueando?** Registros del balanceador (`enforcedSecurityPolicy`).

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| 502 | Backends no sanos | Firewall y chequeo |
| 404 del balanceador | Sin regla para host/ruta | URL map |
| Certificado `PROVISIONING` | DNS no apunta aún | Corrige DNS y espera |
| 403 | Cloud Armor | Revisa la regla |
| 504/cortes | Timeout del backend | Ajusta |
