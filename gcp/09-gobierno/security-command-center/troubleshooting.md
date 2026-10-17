# Google Cloud · Gobierno · Security Command Center · Troubleshooting

## Lista ordenada
1. **¿Nivel y servicios activos?** Algunos detectores son solo Premium/Enterprise.
2. **¿Ámbito?** Activado a nivel de organización o solo de proyecto.
3. **¿El hallazgo sigue ACTIVE tras corregir?** Los escáneres tardan en volver a pasar.
4. **¿Mute?** Revisa reglas que lo oculten.
5. **¿Notificaciones?** Filtro de la configuración y permisos del tema de Pub/Sub.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| No aparecen amenazas | Nivel o detector inactivo | Activa el servicio |
| Hallazgo no se cierra | Escaneo pendiente | Espera el ciclo o marca como inactivo |
| No llega a Pub/Sub | Filtro o permisos | Revisa la configuración de notificación |
| Hallazgo oculto | Mute | Revisa reglas |
| `PERMISSION_DENIED` al listar | Rol | `findingsViewer` en la organización |
