# NotebookLM · Azure · Bloqueos de recursos

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/` (Terraform, CLI y KQL).

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre los bloqueos de recursos de Azure (Resource Locks), para un ingeniero Java de microservicios que quiere dominarlos de inicio a fin. No compares con otras nubes ni con herramientas equivalentes de otras nubes.

Estructura obligatoria:
1. Qué es un bloqueo y qué problema resuelve; la analogía del cubre-interruptor; los dos niveles, CanNotDelete y ReadOnly; el diagrama de herencia desde la suscripción hasta el recurso.
2. Cómo funciona por dentro: se evalúa en Azure Resource Manager por encima de RBAC; solo el plano de control (no el de datos); herencia y "gana el más restrictivo"; recursos de extensión; borrar un grupo con un recurso bloqueado falla completo; no se pueden poner en grupos de administración.
3. Quién puede crear y quitar bloqueos: Microsoft.Authorization/locks/*, Owner y User Access Administrator, por qué Contributor no puede, y el rol personalizado "Administrador de bloqueos"; separación de funciones y PIM.
4. La tabla de lo que se rompe con ReadOnly y con CanNotDelete: almacenamiento (List Keys), App Service y escalado, máquinas virtuales, Automation, Backup, el límite de 800 despliegues, asignaciones de roles, Application Gateway, AKS, Log Analytics, PostgreSQL y aplicaciones administradas.
5. Bloqueos frente a otras protecciones: política DenyAction, Deployment Stacks con denySettings, asignaciones de denegación, borrado suave y protección contra purga, copias de seguridad y RBAC; cuándo usar cada una.
6. Bloqueos como código con Terraform: azurerm_management_lock, depends_on, la variable "proteger" para el borrado controlado, el rol personalizado, las alertas del registro de actividad y la política DenyAction como segunda capa.
7. Cómo se ve el error ScopeLocked y cómo distinguirlo de AuthorizationFailed, RequestDisallowedByPolicy y el 403 de DenyAction.
8. Los 12 casos reales como historias con su lección: el grupo equivocado, el ReadOnly que impidió escalar, el Terraform que no podía destruir, la copia de seguridad que dejó de limpiar, los 800 despliegues, el Owner que no podía borrar, quien despliega no debe quitar el candado, el bloqueo en el almacenamiento y las claves, la limpieza automática, el bloqueo olvidado, las bajas de personas y las pilas de despliegue.
9. Código Java: leer ScopeLocked y extraer los alcances bloqueados, listar y proteger de forma idempotente, auditar los grupos de producción sin bloqueo, el borrado controlado con ticket y restauración, pilas de despliegue con denySettings, métrica en Micrometer, WebFlux con boundedElastic, Quarkus imperativo y reactivo con Mutiny; pruebas.
10. CLI y KQL: crear, listar y probar bloqueos; consultas del registro de actividad para saber quién quitó un bloqueo y el patrón sospechoso "quitar y borrar"; Resource Graph.
11. Qué hacer y qué NO hacer; límites (20 por alcance), costo cero y la alternativa a Blueprints.
12. Tabla de troubleshooting por síntoma y secuencia de diagnóstico.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
