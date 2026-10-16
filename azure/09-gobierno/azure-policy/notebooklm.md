# NotebookLM · Azure · Azure Policy

**Fuentes a subir:** todos los `.md` de esta carpeta (incluido `catalogo-net-01-12.md`) y los archivos de `ejemplos/` (Terraform, CLI, JSON de definiciones, KQL y Resource Graph).

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure Policy, para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes ni con herramientas equivalentes de otras nubes.

Estructura obligatoria:
1. Qué es Azure Policy y qué problema resuelve; la analogía del reglamento de construcción y el inspector; diferencia entre RBAC y Policy; diagrama de objetos: definición, iniciativa, asignación, exención, atestación, cumplimiento y remediación.
2. Anatomía de una definición: modo (All, Indexed y modos de proveedor), parámetros, condiciones y operadores, count, alias y cómo descubrirlos, metadatos y versiones.
3. Todos los efectos con ejemplos: Audit, AuditIfNotExists, Deny, DenyAction, Modify, Append, DeployIfNotExists, Manual, Disabled, Mutate y AddToNetworkGroup; el orden de evaluación.
4. Cuándo se evalúa: al crear o modificar, tras asignar, ciclo de 24 horas y bajo demanda; estados de cumplimiento.
5. Alcance y herencia: grupos de administración, suscripciones, grupos de recursos; ubicación de la definición; notScopes frente a exenciones; categorías Waiver y Mitigated; caducidad.
6. Asignaciones: modo de aplicación (DoNotEnforce), mensajes de no conformidad, parámetros, selectores de recursos y sobrescrituras, identidad administrada.
7. Remediación: identidad, roleDefinitionIds, quién concede los roles según el método (portal, Terraform, CLI, SDK) y las tareas de remediación.
8. Azure Policy para Kubernetes con Gatekeeper; relación con Defender for Cloud, Resource Graph, registro de actividad y Event Grid.
9. Política como código y estrategia de adopción: Audit, medir, comunicar, Deny por entornos, remediación; límites del servicio.
10. El catálogo de reglas de red NET-01 a NET-12 de ModaLima mapeado a políticas integradas reales y a qué grupo de administración va cada una.
11. Los 13 casos reales como historias con su lección: IP públicas en Corp, etiquetas, regiones y Front Door, error de despliegue, 200 recursos antiguos, remediación fallida, el ensayo que evitó un apagón, la exención de dos años, la política que no hacía nada, quitar la política en la suscripción, diagnósticos que subieron la factura, Terraform contra Modify y Gatekeeper contra el agente de monitoreo.
12. Código Java: leer el error RequestDisallowedByPolicy (también anidado), resumen e incumplimientos con PolicyInsights, consultas de Resource Graph, autoservicio de entornos con respuesta 422, métrica en Micrometer, exenciones con caducidad, WebFlux con boundedElastic, Quarkus imperativo y reactivo con Mutiny; pruebas.
13. Ejemplos de Terraform (iniciativa, asignación, Modify con remediación, exención, alertas), CLI, JSON de definiciones y KQL; qué hacer y qué NO hacer; límites, costos y retiro de Blueprints.
14. Tabla de troubleshooting por síntoma y secuencia de diagnóstico.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
