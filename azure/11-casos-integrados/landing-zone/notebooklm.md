# NotebookLM · Azure · Caso integrado · Landing zone

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/` (el módulo de Terraform y su composición, JSON, CLI, SQL y consultas).

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre cómo construir en Azure una zona de aterrizaje (landing zone) con entrega automática de suscripciones, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. La analogía del barrio planificado; el diagrama de la jerarquía de grupos de administración y del módulo de suscripción de carga.
2. El proceso de punta a punta en ocho pasos: solicitud, asignación de red, variables, creación de la suscripción, revisión, aplicación, verificación y bienvenida.
3. Qué hace el módulo recurso por recurso y por qué: asociación al grupo, grupos de recursos, red con peering en ambos sentidos, registro de actividad, roles mínimos, presupuesto y bloqueo; por qué las políticas viven en el grupo y no en el módulo.
4. Terraform: proveedores con alias por suscripción, módulos, validaciones y las limitaciones.
5. El problema de las direcciones IP: solapamientos, asignador, clave primaria y carreras, idempotencia.
6. El verificador: reglas del checklist, de dónde sale cada dato, deriva y alertas.
7. Seguridad: tabla de permisos por plano, amenazas y defensas.
8. Qué hacer y qué NO hacer, costos y límites.
9. Los siete casos reales como historias con su lección.
10. Código Java: Cidr, asignador, solicitud validada, generador de variables, registro con JDBC, servicio, checklist, Spring MVC y WebFlux, Quarkus imperativo y reactivo, y las pruebas.
11. Troubleshooting por síntoma y la secuencia de diagnóstico.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
