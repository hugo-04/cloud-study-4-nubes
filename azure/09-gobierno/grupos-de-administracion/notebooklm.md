# NotebookLM · Azure · Grupos de administración

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/` (Terraform, CLI y KQL).

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre los grupos de administración de Azure (Management Groups), para un ingeniero Java de microservicios que quiere dominarlos de inicio a fin. No compares con otras nubes ni con herramientas equivalentes de otras nubes.

Estructura obligatoria:
1. Qué es un grupo de administración y qué problema resuelve; la analogía del edificio con reglamento por piso; el diagrama de la jerarquía de ModaLima (raíz del tenant, raíz intermedia, plataforma, landing zones Corp y Online, sandbox, desmantelado).
2. Cómo funciona por dentro: una jerarquía por tenant, un solo padre, 10 000 grupos y seis niveles; el ID que no se puede cambiar; borrar solo si está vacío; el Tenant Root Group (ID igual al tenant, no se mueve ni se borra, nadie tiene acceso por defecto) y cómo se eleva el acceso.
3. Herencia: Azure RBAC y Azure Policy hacia abajo, por qué el dueño de una suscripción no puede quitar una política del grupo, definiciones personalizadas y despliegues a nivel de grupo; las etiquetas no se heredan; la tabla de roles sobre el grupo.
4. Mover suscripciones: permisos en el elemento, el origen y el destino, la excepción de la raíz, Owner heredado frente a directo, la caché de 30 minutos y el cuidado de ensayar las políticas del grupo destino.
5. Configuración de la jerarquía: grupo predeterminado y exigir autorización para crear grupos; el rol Hierarchy Settings Administrator; portal, REST, CLI, PowerShell y Terraform con AzAPI.
6. Roles personalizados en un grupo y sus tres limitaciones; la auditoría con el registro de actividad.
7. Diseño recomendado de la guía de zonas de aterrizaje y los anti-patrones: copiar el organigrama, grupos por entorno, grupos por región, RBAC de equipos en grupos, muchas políticas en la raíz, suscripciones bajo la raíz, cualquiera creando grupos.
8. Relación con Azure Policy, RBAC, Resource Graph, costos, Defender for Cloud y los bloqueos (que no se pueden poner en un grupo).
9. Los 13 casos reales como historias con su lección: quince suscripciones sin estructura, el organigrama convertido en jerarquía, grupos por entorno, treinta políticas en la raíz, mover una suscripción y cambiar su cumplimiento, la suscripción que nació sin reglas, los grupos Prueba1, el desarrollador que veía los pagos, el rol con un grupo inexistente, elevar acceso para recuperar la raíz, la caché de 30 minutos, el alta en 20 minutos y la baja ordenada.
10. Código Java: por qué el SDK de grupos está solo en beta y qué usar; el cliente REST con el pipeline de azure-core y su prueba contra un servidor falso; el revisor de higiene de la jerarquía como función pura; inventario con Resource Graph; el movimiento de suscripciones con ticket y validación del destino; métrica en Micrometer; WebFlux con boundedElastic; Quarkus imperativo y reactivo con Mutiny; pruebas.
11. Ejemplos de Terraform (jerarquía, asociaciones de suscripciones, políticas por capas, RBAC, ajustes de la raíz), CLI y consultas de Resource Graph; qué hacer y qué NO hacer; límites y costo cero.
12. Tabla de troubleshooting por síntoma y secuencia de diagnóstico.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
