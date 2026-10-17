# NotebookLM · AWS · AWS Organizations y SCP

**Fuentes a subir:** los `.md` de esta carpeta y `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre AWS Organizations y las políticas de control de servicio (SCP), para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. La analogía del reglamento del edificio y el diagrama del árbol de OU con el permiso efectivo como intersección.
2. Organización, cuenta de administración, cuentas miembro, raíz y OU, SCP, FullAWSAccess, lista de denegación frente a lista de permitidos, evaluación, otros tipos de política, administrador delegado, creación de cuentas y qué no limitan las SCP.
3. Cuándo usarlo y cuándo no (SCP frente a IAM, a Config y a CloudTrail).
4. Seguridad: la cuenta de administración, el rol de emergencia, corrección de bloqueos.
5. Qué hacer y qué no; las SCP típicas: regiones con NotAction, proteger trazas y Config, no salir de la organización, exigir IMDSv2, restringir al usuario raíz.
6. Los seis casos reales como historias con su lección.
7. Java: validador de SCP, generador de la SCP de regiones, inventario del árbol de cuentas, creación idempotente de políticas; Spring (MVC y WebFlux) y Quarkus (imperativo y Mutiny).
8. Troubleshooting en orden.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
