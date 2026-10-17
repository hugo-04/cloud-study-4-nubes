# Google Cloud · Red · Firewall, rutas y Cloud NAT · Troubleshooting

## Lista ordenada
1. **¿Qué regla aplica?** Connectivity Tests o `gcloud compute firewall-rules list --filter=network:<red>` ordenadas por prioridad.
2. **¿Política jerárquica?** Puede denegar antes que tus reglas de VPC.
3. **¿Objetivo correcto?** Cuenta de servicio o etiqueta de la VM destino.
4. **¿Origen correcto?** Rangos del balanceador/IAP o cuenta de servicio de origen.
5. **¿Ruta?** Ruta más específica y de menor prioridad gana.
6. **¿NAT?** La subred incluida en el NAT y puertos disponibles.
7. **¿Logs?** Activa logging de la regla y revisa.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Timeout de entrada | Falta regla de allow | Regla por SA desde el origen |
| Bloqueo inesperado | Deny jerárquico | Revisa políticas de la carpeta/organización |
| Sin salida a Internet | Sin NAT o subred no incluida | Configura NAT |
| Fallos de salida intermitentes | Puertos NAT agotados | Más puertos / dinámico |
| Tráfico por ruta equivocada | Ruta personalizada con prioridad | Revisa rutas |
