# Oracle OCI · IAM · Identity Domains · Casos reales

## 1. La exempleada que seguía entrando
**Qué pasó:** una exdesarrolladora aún tenía acceso a dev meses después.
**Causa:** usuarios locales fuera del IdP; nadie los desactivó.
**Arreglo:** SSO con el IdP y revisión de inactivos.
**Lección:** el offboarding vive donde nace la identidad.

## 2. MFA «opcional»
**Qué pasó:** credenciales filtradas de un administrador sin segundo factor.
**Causa:** MFA solo recomendado.
**Arreglo:** política de inicio de sesión que lo exige.
**Lección:** lo opcional no se usa.

## 3. La URL equivocada
**Qué pasó:** una herramienta listaba cero usuarios.
**Causa:** apuntaba al dominio `Default`; los usuarios estaban en otro dominio.
**Arreglo:** URL del dominio como configuración por entorno.
**Lección:** cada dominio tiene su propio endpoint.

## 4. Grupo sin prefijo
**Qué pasó:** la política parecía correcta y no funcionaba.
**Causa:** el grupo estaba en un dominio distinto de `Default`.
**Arreglo:** `'Dominio'/'Grupo'` en la frase.
**Lección:** en políticas, el grupo se nombra con su dominio.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Acceso de exempleada | Usuarios locales | SSO + revisión |
| 2 | Credenciales filtradas | MFA opcional | Exigir MFA |
| 3 | Lista vacía | Endpoint equivocado | URL por entorno |
| 4 | Política sin efecto | Falta el dominio | Prefijo de dominio |
