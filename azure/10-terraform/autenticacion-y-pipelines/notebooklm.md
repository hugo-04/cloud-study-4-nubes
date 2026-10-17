# NotebookLM · Azure · Terraform · Autenticación y pipelines

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/` (Terraform, workflows de GitHub Actions, Azure DevOps, CLI, HCL, JSON y KQL).

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre cómo autenticar y ejecutar Terraform en Azure desde pipelines (GitHub Actions y Azure DevOps) con federación OIDC, para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes ni con herramientas equivalentes de otras nubes.

Estructura obligatoria:
1. Qué es: el problema del secreto de cliente, la federación de identidad de carga de trabajo, la analogía del pase de visitante, el diagrama del intercambio de tokens.
2. Cómo funciona por dentro: los pasos del intercambio, los campos issuer, audience y subject, los límites (20 credenciales, sin comodines, subject mal escrito sin error), qué subject emite cada disparador, la regla del entorno, las variables ARM_*, los métodos de autenticación, identidad administrada frente a registro de aplicación.
3. Para qué sirve y cuándo no.
4. Cómo se usa: dos identidades por entorno, roles de control y de datos, administrador de RBAC con condición, los seis pasos de puesta en marcha, la anatomía del pipeline (plan en el PR, plan guardado, aprobación, apply, deriva nocturna), concurrencia, ejecutores propios, puertas de calidad (fmt, validate, tflint, trivy, checkov, conftest, infracost), Azure DevOps.
5. Seguridad: la tabla de IAM por plano, el modelo de amenazas (quien edita el workflow manda, PR de forks, subject amplio, apply sin revisión, escalada de privilegios, plan con secretos, identidad compartida).
6. Qué hacer y qué NO hacer; límites, costos, propagación y versiones.
7. Los 11 casos reales como historias con su lección: el secreto que caducó un viernes, el AADSTS70021 por un entorno mal escrito, el plan de PR que podía leer producción, el apply sin aprobación en dev, el AuthorizationFailed al asignar roles, el apply cancelado, el ejecutor público contra el firewall, el plan guardado obsoleto, el artefacto del plan con una contraseña, la política que detuvo el borrado de la base de datos y el drift nocturno.
8. Código Java: el analizador de planes (terraform show -json) con reglas de borrado protegido, roles privilegiados, exposición pública y mensajes que no filtran valores; el ejecutor de procesos con tiempo límite y variables de entorno permitidas; Spring MVC, WebFlux y Quarkus imperativo y reactivo; las pruebas.
9. Ejemplos: el Terraform de identidades, los workflows, el pipeline de Azure DevOps, el script de CLI, las consultas KQL.
10. Tabla de troubleshooting por síntoma, con los códigos AADSTS, y la secuencia de diagnóstico.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
