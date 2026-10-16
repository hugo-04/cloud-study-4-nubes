# Azure · RBAC · Casos reales

## Caso 1 · "Soy Contributor y no puedo leer los blobs"
- **Problema:** una desarrolladora de ModaLima con Contributor no podía abrir los archivos del storage con su usuario.
- **Causa:** Contributor es del plano de control; leer datos requiere un rol de datos.
- **Solución:** *Storage Blob Data Reader* al grupo, solo sobre el contenedor necesario.
- **Lección:** tener permiso sobre el recurso no es tener permiso sobre sus datos.

## Caso 2 · Owner a toda la suscripción
- **Problema:** una auditoría encontró 14 personas con Owner en la suscripción de producción.
- **Solución:** crear grupos por función; Contributor por Resource Group; Owner solo por PIM con aprobación y fecha límite.
- **Resultado:** de 14 Owners permanentes a 2 elegibles.
- **Lección:** el privilegio permanente es deuda de seguridad.

## Caso 3 · "Ya asigné el rol y sigue fallando"
- **Problema:** se asignó *Key Vault Secrets User* a una aplicación y seguía recibiendo 403.
- **Causa:** propagación (unos minutos) y un token en caché con permisos viejos.
- **Solución:** esperar y reiniciar la aplicación para forzar un token nuevo.
- **Lección:** RBAC no es instantáneo; planifica el despliegue.

## Caso 4 · Rol personalizado para soporte
- **Problema:** el equipo de soporte necesitaba reiniciar App Services y ver logs, nada más.
- **Solución:** rol personalizado con `Microsoft.Web/sites/restart/action` y `Microsoft.Insights/*/read`, asignado a un grupo en el RG de producción.
- **Lección:** cuando ningún rol integrado encaja, un rol pequeño y revisado es mejor que Contributor.

## Caso 5 · Delegar sin perder el control
- **Problema:** los líderes de equipo debían asignar roles de datos, pero no Owner.
- **Solución:** *Role Based Access Control Administrator* con **condición ABAC** que solo permite asignar roles de datos concretos.
- **Lección:** delegación acotada con condiciones.

## Caso 6 · El pipeline con demasiado poder
- **Problema:** el pipeline de despliegue tenía Owner de la suscripción.
- **Solución:** Contributor solo en los RG de la aplicación + *User Access Administrator* acotado a las asignaciones que el despliegue necesita (con condición).
- **Lección:** los pipelines también merecen mínimo privilegio.
