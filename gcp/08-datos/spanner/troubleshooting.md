# Google Cloud · Datos · Spanner · Troubleshooting

## Lista ordenada
1. **¿CPU alta?** Monitoreo de la instancia; > 65 % en multirregión es señal de escalar *(verifica)*.
2. **¿Hotspots?** Key Visualizer.
3. **¿Abortos?** Estadísticas de bloqueos y transacciones; ¿transacciones largas?
4. **¿Consultas lentas?** Query Insights y planes; índices.
5. **¿Permisos?** `databaseUser` en la base.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `ABORTED` frecuente | Contención | Transacciones cortas, menos filas calientes |
| Latencia de escritura | Hotspot | Cambia la PK |
| `DEADLINE_EXCEEDED` | Consulta pesada | Índice o paginación |
| `PERMISSION_DENIED` | IAM | Rol en la base |
| Mutaciones rechazadas | Límite de transacción | Lotes más chicos |
