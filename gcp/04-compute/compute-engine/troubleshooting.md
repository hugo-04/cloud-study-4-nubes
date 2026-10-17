# Google Cloud · Compute · Compute Engine · Troubleshooting

## Lista ordenada
1. **¿Estado?** `gcloud compute instances describe`; registros de la consola serial.
2. **¿Arranca el script de inicio?** `journalctl -u google-startup-scripts` o salida serial.
3. **¿Cuota?** `QUOTA_EXCEEDED` por CPU/IP/disco en la región.
4. **¿Capacidad?** `ZONE_RESOURCE_POOL_EXHAUSTED`: otra zona o familia.
5. **¿SSH?** IAP (`35.235.240.0/20` en firewall), rol de OS Login.
6. **¿La app llega a APIs?** PGA/NAT y roles de la cuenta de servicio.
7. **¿MIG reemplaza VMs en bucle?** Chequeo de salud demasiado estricto o app que tarda en arrancar.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| No crea VM | Cuota o capacidad | Pide cuota / cambia zona |
| SSH falla | Firewall de IAP u OS Login | Regla y rol |
| VM se reinicia sola | Spot interrumpida o mantenimiento | Política de disponibilidad |
| MIG en bucle | `initialDelaySec` corto | Aumenta el retraso inicial |
| 403 en APIs | Rol o alcance | Rol en IAM + `cloud-platform` |
