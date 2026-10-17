# Google Cloud · Caso integrado · Clickstream · Troubleshooting

## Lista ordenada
1. **¿El colector produce?** Errores SASL o de red hacia el bootstrap.
2. **¿El tema recibe?** Offsets finales creciendo.
3. **¿El grupo avanza?** Lag por partición (`consumer-groups describe`).
4. **¿Ventanas cerradas?** Marca de agua estancada = no llegan eventos nuevos.
5. **¿La caché se escribe?** Errores de Memorystore.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Lag creciente | Consumidor lento | Lotes, más instancias (≤ particiones) |
| Muchos tardíos | Retraso permitido corto | Ajusta la marca de agua |
| Rebalanceos | Procesamiento largo | Sube `max.poll.interval.ms` |
| Top vacío | Commit sin escritura | Revisa el orden escribir→commit |
| Errores SASL | Login handler/rol | Ver Managed Kafka |
