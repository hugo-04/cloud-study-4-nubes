# AWS · IAM · Roles y políticas · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. La clave de acceso en GitHub
**Qué pasó:** un desarrollador subió un `.env` con una clave de larga duración; en 20 minutos había instancias minando criptomonedas. **Solución:** revocar la clave, eliminar claves de larga duración, roles con credenciales temporales y escaneo de secretos en el repositorio. **Lección:** la mejor clave es la que no existe.

## 2. `"Resource": "*"` en `iam:PassRole`
**Qué pasó:** un rol de pipeline podía pasar cualquier rol a cualquier servicio y alguien lanzó una función con el rol de administrador. **Solución:** `PassRole` solo al ARN del rol de la función y condición `iam:PassedToService`. **Lección:** `PassRole` es una escalera.

## 3. El Deny que nadie veía
**Qué pasó:** «tengo AdministratorAccess y no puedo crear un bucket en São Paulo». **Causa:** una SCP de la organización negaba regiones no aprobadas. **Solución:** mostrar el origen del `Deny` con el simulador y la documentación de errores. **Lección:** hay más capas que la política de tu rol.

## 4. Acceso entre cuentas a medias
**Qué pasó:** la cuenta B tenía permisos en su rol pero el bucket de A respondía `AccessDenied`. **Causa:** faltaba la política de recurso en el bucket. **Solución:** política de bucket con `aws:PrincipalOrgID`. **Lección:** entre cuentas, **los dos lados**.

## 5. Permisos que crecían sin límite
**Qué pasó:** cada equipo creaba roles y se daba permisos de administrador «para ir rápido». **Solución:** límite de permisos obligatorio al crear roles (condición en `iam:CreateRole`) y revisión de permisos sin uso con Access Analyzer. **Lección:** delegar con tope.

## 6. ABAC que ahorró 200 políticas
**Qué pasó:** una política por proyecto, cada una copia de la anterior. **Solución:** etiqueta `proyecto` en roles y recursos y una sola política con `aws:PrincipalTag/proyecto = aws:ResourceTag/proyecto`. **Lección:** etiquetas bien gobernadas sustituyen cientos de políticas.

| Problema | Solución |
|---|---|
| Claves filtradas | Roles + escaneo de secretos |
| Escalada por `PassRole` | Recurso concreto + condición |
| Deny invisible | Simulador y capas |
| Cross-account a medias | Política de recurso + rol |
| Roles sin tope | Límite de permisos |
| Explosión de políticas | ABAC |
