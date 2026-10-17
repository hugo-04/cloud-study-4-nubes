# NotebookLM · AWS · Terraform · Estado remoto (S3)

**Fuentes a subir:** los `.md` de esta carpeta y `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre el estado remoto de Terraform en AWS (backend S3), para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. La analogía del libro de obra y el diagrama de código, plan, estado en S3, candado y recursos reales.
2. Qué contiene el estado (serial, lineage, secretos en texto claro), el backend s3, el bloqueo nativo con use_lockfile, versionado, cifrado con KMS, la convención de claves por entorno y componente, terraform_remote_state, moved, import y removed, workspaces y por qué no separan entornos.
3. Cuándo usarlo y cuándo no (el estado no es una bóveda ni un inventario).
4. Seguridad: bucket dedicado, permisos por prefijo, KMS, política que exige TLS y niega borrar versiones, sin acceso humano, auditoría con CloudTrail.
5. Qué hacer y qué no; recuperación ante desastres y force-unlock con criterio.
6. Los seis casos reales como historias con su lección.
7. Java: auditor del bucket del estado (versionado, cifrado, bloqueo de acceso público, política TLS, locks colgados, claves fuera de convención); Spring (MVC y WebFlux) y Quarkus (imperativo y Mutiny).
8. Troubleshooting en orden.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
