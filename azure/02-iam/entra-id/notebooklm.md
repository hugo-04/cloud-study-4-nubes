# NotebookLM · Azure · Microsoft Entra ID

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Microsoft Entra ID para proteger microservicios, para un ingeniero Java. No compares con otras nubes.

Estructura obligatoria:
1. Qué es Entra ID con la analogía del edificio, la recepción y el gafete.
2. Objetos del directorio: tenant, usuarios, grupos, app registration, service principal y managed identity. Explica con claridad la diferencia entre app registration y service principal.
3. OAuth 2.0 y OpenID Connect: los flujos (authorization code con PKCE, client credentials, on-behalf-of, device code) y cuándo se usa cada uno.
4. Anatomía de un JWT: cada claim (iss, aud, sub, oid, tid, scp, roles, exp) y qué valida una API.
5. Scopes frente a app roles, y cómo se expone y consume una API protegida.
6. Seguridad de personas: MFA, Conditional Access, PIM, revisiones, cuentas break-glass.
7. Cómo se crea todo: CLI y Terraform con el código de las fuentes.
8. Los 5 casos reales como historias.
9. Código Java: resource server con Spring Boot imperativo y reactivo, Quarkus OIDC, validación de audiencia, client credentials con azure-identity y MSAL4J.
10. Qué hacer, qué NO hacer y la tabla de errores AADSTS.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; cierra con 3 puntos de resumen y 2 preguntas de repaso.
```
