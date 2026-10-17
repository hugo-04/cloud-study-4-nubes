# Google Cloud · IAM · Roles y políticas · Repaso

## Preguntas
1. ¿Qué une un binding?
2. ¿Qué tipos de rol existen?
3. ¿Cómo se combinan las políticas heredadas?
4. ¿Qué hace una política de denegación?
5. ¿Para qué sirven las condiciones?
6. ¿Por qué grupos y no usuarios?
7. ¿Qué diferencia hay entre `iam_member` e `iam_policy` en Terraform?
8. ¿Qué herramienta explica un 403?
9. ¿Qué es `allAuthenticatedUsers`?
10. ¿Cómo se evita la sobrescritura concurrente de una política?

## Respuestas
1. Un rol con miembros y, opcionalmente, una condición.
2. Básicos, predefinidos y personalizados.
3. Se suman (unión), salvo denegaciones.
4. Niega permisos aunque un rol los otorgue.
5. Para limitar por recurso, tiempo o tags.
6. Facilitan altas/bajas y auditoría.
7. `iam_member` agrega; `iam_policy` reemplaza todo.
8. Policy Troubleshooter.
9. Cualquier cuenta de Google autenticada.
10. Con el ETag.

## Ejercicios
1. Diseña los grupos y roles de ModaLima para prod y no-prod.
2. Escribe un rol personalizado para el equipo de soporte.
3. Escribe una condición de acceso temporal de 7 días.
