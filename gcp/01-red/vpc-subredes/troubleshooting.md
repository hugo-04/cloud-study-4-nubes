# Google Cloud · Red · VPC y subredes · Troubleshooting

## Lista ordenada
1. **¿Misma VPC?** Si no, hace falta peering, VPN o Interconnect.
2. **¿Firewall?** Dentro de la VPC, el firewall decide (la entrada está denegada por defecto).
3. **¿Rutas?** `gcloud compute routes list`; rutas personalizadas con prioridad.
4. **¿PGA?** Para APIs de Google sin IP externa.
5. **¿IPs agotadas?** Uso de la subred y de rangos secundarios.
6. **¿Shared VPC?** El proyecto de servicio necesita `networkUser` sobre la subred.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Sin conectividad entre VMs | Firewall | Regla de entrada |
| `IP_SPACE_EXHAUSTED` | Subred llena | Amplía el rango |
| Error al crear VM en subred compartida | Falta `networkUser` | Rol por subred |
| VM sin acceso a APIs | Sin PGA ni NAT | Activa PGA |
| Peering rechazado | Rangos solapados | Replanifica |
