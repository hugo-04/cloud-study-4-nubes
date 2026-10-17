# Azure · Caso integrado · Landing zone · Troubleshooting

Orden: **¿la suscripción está en su grupo? → ¿heredó las políticas? → ¿el pipeline tiene permisos? → ¿la red se conectó? → ¿el equipo ve lo que debe?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `AuthorizationFailed` al asociar la suscripción | La identidad del pipeline no escribe en el grupo de administración | Roles en el grupo destino | Permiso sobre el grupo (no solo sobre la suscripción) |
| El proveedor falla con `subscription_id is required` | `azurerm` 4 sin suscripción en el alias | Bloque `provider` | Definir `subscription_id` en cada alias |
| `Provider configuration not present` al quitar un equipo | Se borró la llamada al módulo con recursos aún en el estado | `terraform state list` | Destruir primero o usar `removed` con cuidado |
| Peering en «Initiated» | Falta el lado del hub (o permisos en esa suscripción) | `az network vnet peering list` | Crear el segundo lado con el alias de plataforma |
| `Address space overlaps` | Bloque duplicado | Consulta de redes ([KQL 3](ejemplos/kql/kql-aterrizaje.md)) | Reasignar con el servicio de direcciones |
| El portal asigna el mismo bloque a dos equipos | Falta la clave primaria o se hizo en memoria | Esquema de la tabla | Restricción única en la base |
| La suscripción no hereda las políticas | Quedó en el grupo raíz o en otro grupo | Consulta de ancestros ([KQL 1](ejemplos/kql/kql-aterrizaje.md)) | Reasociar al grupo correcto; esperar a la evaluación |
| Despliegues del equipo rechazados por política | `Deny` esperado (p. ej. IP pública) | Mensaje de política en el registro de actividad | Usar Private Endpoint; si es legítimo, exención con fecha |
| `Reader` en la suscripción pero no ve recursos de otros grupos | Es lo esperado | — | Documentar lo que NO ven |
| Presupuesto no envía correos | Contactos vacíos o fecha de inicio incorrecta | Presupuesto en el portal | Contactos válidos; inicio el primer día del mes |
| `terraform plan` quiere recrear el presupuesto | Cambia `start_date` con cada plan | Salida del plan | `ignore_changes = [time_period]` (ya incluido) |
| Diagnóstico de la suscripción falla | Falta permiso o categorías no disponibles | Mensaje de error | Rol *Monitoring Contributor*; revisar categorías de tu entorno |
| El bloqueo impide un cambio legítimo | `CanNotDelete` vs `ReadOnly` | Tipo de bloqueo | Quitar con solicitud de cambio, hacer el cambio y volver a poner |
| El checklist da falsos `ACCESO_PUBLICO` | Recursos de prueba en Online/Corp | Recurso concreto | Corregir el recurso o registrar la excepción con caducidad |
