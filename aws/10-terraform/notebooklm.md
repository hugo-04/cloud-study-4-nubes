# NotebookLM · AWS · Capítulo 10 Terraform en AWS

**Fuentes a subir:** este `README.md` y los de las tres carpetas de servicio (Estado remoto, Autenticación y pipelines, Módulos y entornos).

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, sobre Terraform en AWS para un ingeniero Java de microservicios. Solo AWS; no compares con otras nubes.

Estructura obligatoria:
1. La idea central: infraestructura como código que se revisa, se prueba y se repite, y las tres piezas que la hacen segura: estado remoto, identidad del pipeline y módulos con entornos. Usa las analogías del libro de obra, el pase de visitante y la receta con sus cocinas.
2. Estado remoto en S3: qué contiene, candado nativo, versionado, KMS, claves por entorno y componente, moved, import, removed.
3. Autenticación con OIDC: proveedor, token, aud y sub, política de confianza, roles de plan y apply, límite de permisos, entornos protegidos, puerta de seguridad, deriva nocturna.
4. Módulos y entornos: contrato con validation, versión fija, for_each con mapa, carpetas por entorno, terraform test con proveedor simulado.
5. La tabla comparativa, el árbol de decisión y la receta de ModaLima paso a paso, con el orden de adopción.
6. Los casos reales más importantes de cada servicio como historias con su lección.
7. Java: auditor del bucket del estado, analizador de planes y validador de confianza OIDC, validador de solicitudes y generador determinista de tfvars con prueba de contrato; Spring (MVC y WebFlux) y Quarkus (imperativo y Mutiny).
8. Errores comunes y troubleshooting.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima y Café Andino; cierra con 8 puntos de resumen y 5 preguntas de repaso.
```
