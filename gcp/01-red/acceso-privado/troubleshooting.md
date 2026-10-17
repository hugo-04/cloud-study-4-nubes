# Google Cloud · Red · Acceso privado · Troubleshooting

## Lista ordenada
1. **¿Qué IP resuelve el nombre?** `dig storage.googleapis.com` desde la VM.
2. **¿PGA activo en la subred?**
3. **¿Ruta a las VIP o al endpoint?** Ruta por defecto interna o ruta específica a `199.36.153.x`.
4. **¿Firewall de salida?** Si restringes salida, permite los rangos/endpoint.
5. **¿Zona privada ligada a la VPC correcta?**
6. **¿PSA conectado?** `gcloud services vpc-peerings list`.
7. **¿IAM?** El camino privado no da permisos.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Timeout a APIs | Sin PGA/NAT | Activa PGA |
| Resuelve IP pública con PSC | Falta zona privada | Crea la zona |
| `403 VPC Service Controls` | Fuera del perímetro | Revisa perímetro y VIP restringida |
| Cloud SQL privada no se crea | Sin PSA o rango lleno | Conexión de servicenetworking |
| Oficina no resuelve | Sin reenvío | Política DNS entrante |
