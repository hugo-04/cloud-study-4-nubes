# NotebookLM · Azure · Managed Identity

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure Managed Identity para microservicios Java.
No compares con otras nubes.

Estructura obligatoria:
1. Qué es una managed identity, con la analogía del gafete que la plataforma crea y renueva.
2. Cómo funciona por dentro paso a paso: el endpoint local de identidad, IMDS, el token, y cómo el servicio evalúa RBAC. Dibuja el flujo.
3. System-assigned frente a user-assigned: tabla de diferencias y cuándo elegir cada una.
4. Client ID, principal ID y por qué importa la diferencia.
5. Qué recursos la soportan y cuándo NO usarla (código fuera de Azure, pods de AKS).
6. Cómo se crea: CLI y Terraform con el código de las fuentes, y por qué la identidad y sus roles se crean antes de la aplicación.
7. Los 6 casos reales como historias.
8. Código Java: DefaultAzureCredential, un solo cliente reutilizable, Spring Boot imperativo y reactivo, Quarkus, bases de datos sin contraseña (Azure SQL y PostgreSQL).
9. Qué hacer, qué NO hacer y troubleshooting.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; cierra con 3 puntos de resumen y 2 preguntas de repaso.
```
