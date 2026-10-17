# Oracle OCI · Caso integrado · Clickstream · Troubleshooting

## Lista ordenada
1. **¿Llegan eventos al colector?** Métricas del gateway (429 por límite de tasa).
2. **¿Se publican?** Fallos parciales en `PutMessages`.
3. **¿El grupo lee?** Lag por partición; instancias activas en el grupo.
4. **¿Ventanas vacías?** Relojes de clientes desfasados o marca de agua mal calculada.
5. **¿El conector copia?** Estado del Service Connector y permisos al bucket.
6. **¿Throttling?** Particiones insuficientes o clave caliente.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Lag creciente | Consumidor lento | Más instancias (≤ particiones), lotes |
| Ventanas con pocos datos | Eventos tardíos fuera del retraso | Ajusta el retraso permitido |
| Eventos del futuro | Reloj del cliente | Descarta/corrige `ts` > ahora + margen |
| Historial vacío | Conector sin permisos | Política de servicio |
| 429 en el colector | Partición caliente | Clave por sesión |
