# NotebookLM · Azure · Terraform · Estado remoto

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/` (Terraform, CLI, HCL y KQL).

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre el estado remoto de Terraform en Azure (backend azurerm con cuenta de almacenamiento), para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes ni con herramientas equivalentes de otras nubes.

Estructura obligatoria:
1. Qué es el estado y qué problema resuelve; la analogía del libro de obra; el diagrama código, estado y recursos reales; la estructura de contenedor y claves.
2. Cómo funciona por dentro: los campos del archivo de estado (version, serial, lineage, outputs, resources), qué hace cada comando con el estado, el bloqueo con el lease del blob, la configuración parcial del backend, los métodos de autenticación y el rol de datos que pide la documentación.
3. Para qué sirve y cuándo no hace falta; alternativas como HCP Terraform y Bicep con Deployment Stacks.
4. Cómo se usa: el arranque (bootstrap) en cuatro pasos y la migración del estado a sí mismo; cuántos estados y cómo nombrarlos; una cuenta o varias; terraform_remote_state y su riesgo; por qué carpetas y claves en lugar de workspaces; la cirugía del estado con moved, import, removed y refresh-only.
5. Seguridad: cuenta sin claves, TLS 1.2, sin acceso anónimo, firewall o Private Endpoint, versionado, borrado suave, bloqueo CanNotDelete, ZRS, diagnóstico; la tabla de IAM por plano; por qué el plan también necesita escribir; redes y ejecutores; los archivos de plan como secretos.
6. Qué hacer y qué NO hacer; límites, costos y compatibilidad de versiones.
7. Los 11 casos reales como historias con su lección: dos apply a la vez, el candado huérfano, el tfstate en el repositorio, el contenedor borrado, el 403 al desactivar las claves, el firewall que dejó fuera a los pipelines, el plan de 25 minutos, renombrar sin destruir, remote_state que mostraba secretos, recuperar el estado de ayer y el estado sin dueño.
8. Código Java: el auditor del estado con el SDK de blobs y el de almacenamiento (inventario con lease, tamaño y último cambio; configuración de la cuenta), las reglas puras de auditoría, el seguimiento de bloqueos, la métrica en Micrometer, Spring MVC, WebFlux y Quarkus imperativo y reactivo, y las pruebas.
9. Ejemplos: el Terraform de arranque, backend.hcl y backend.tf, el script de CLI (inventario, romper lease, versiones, cirugía, cambio de backend) y las consultas KQL de auditoría.
10. Tabla de troubleshooting por síntoma y secuencia de diagnóstico.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
