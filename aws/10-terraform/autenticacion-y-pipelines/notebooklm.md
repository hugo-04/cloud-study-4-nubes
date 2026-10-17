# NotebookLM · AWS · Terraform · Autenticación y pipelines (OIDC)

**Fuentes a subir:** los `.md` de esta carpeta y `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre la autenticación de pipelines de Terraform en AWS con OIDC, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. La analogía del pase de visitante de un solo día y el diagrama de GitHub Actions, token OIDC, STS, rol y recursos.
2. Proveedor OIDC, token y sus claims (aud, sub), política de confianza, roles de plan y apply, límite de permisos, entornos protegidos, multicuenta, puerta de seguridad y deriva nocturna.
3. Cuándo usarlo y cuándo no (personas frente a pipelines).
4. Seguridad: el sub como llave real, comodines peligrosos, StringEquals frente a StringLike, forks, acciones fijadas por hash, aplicar el mismo plan.
5. Qué hacer y qué no; el flujo completo de un cambio desde el PR hasta producción.
6. Los seis casos reales como historias con su lección.
7. Java: analizador de planes (terraform show -json), validador de políticas de confianza OIDC, ejecutor aislado de terraform; Spring (MVC y WebFlux) y Quarkus (imperativo y Mutiny).
8. Troubleshooting en orden.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
