# Oracle OCI · Gobierno · Cloud Guard y Security Zones · Troubleshooting

## Lista ordenada
1. **¿Cloud Guard habilitado?** Estado `ENABLED` y región de reporte definida.
2. **¿El compartimento está en un target?** Si no, no se vigila.
3. **¿Política de servicio?** Cloud Guard necesita leer recursos (y gestionar para corregir).
4. **¿La regla está habilitada en la receta clonada?**
5. **¿Creación rechazada?** Mensaje de Security Zone: indica la política violada.
6. **¿Problema que no se cierra?** El recurso sigue sin cumplir o el detector aún no reevaluó.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| No aparecen problemas | Sin target o deshabilitado | Configura target |
| *Responder* no corrige | Modo notificar o falta permiso | Modo y política |
| Creación falla en prod | Violación de Security Zone | Ajusta el recurso (no la zona) |
| Demasiados problemas | Recetas por defecto sin ajustar | Clona y ajusta con criterio |
| Problema reabierto | El recurso volvió a cambiar | Corrige la causa (IaC) |
