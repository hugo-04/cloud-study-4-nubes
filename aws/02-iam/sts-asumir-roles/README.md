# AWS · IAM · STS y asumir roles

**STS** (Security Token Service) es la «casa de moneda» de credenciales **temporales**: te entrega claves que caducan. **Asumir un rol** es el mecanismo para cruzar cuentas, para que un servicio actúe con permisos concretos y para que casi nada use claves de larga duración.

## 1. Qué es

**Analogía:** un **pase de visitante**. Llegas a la recepción de otro edificio (otra cuenta), muestras quién eres, la recepción revisa en su lista si te corresponde y te imprime un pase con tu nombre y una hora de caducidad. Con ese pase abres solo las puertas del pase. Si lo pierdes, caduca solo.

```
  Cuenta A (111122223333)                       Cuenta B (444455556666)
  rol "pedidos-app"  ──── sts:AssumeRole ────►  rol "lector-logs"
   (permiso: sts:AssumeRole sobre el ARN)         (confianza: permite a pedidos-app)
        ◄──── credenciales temporales (AccessKeyId + SecretKey + SessionToken, 1 h) ────
  s3:GetObject sobre el bucket de B con ese pase
```

## 2. Cómo funciona por dentro

### Las operaciones
| Operación | Para qué |
|---|---|
| `AssumeRole` | Asumir un rol (misma cuenta o entre cuentas) |
| `AssumeRoleWithWebIdentity` | Intercambiar un token OIDC (EKS/IRSA, GitHub Actions, Cognito) por un rol |
| `AssumeRoleWithSAML` | Intercambiar una aserción SAML por un rol |
| `GetCallerIdentity` | «¿Quién soy?» (no requiere permisos) |
| `GetSessionToken` | Credenciales temporales de un usuario IAM (con MFA) |
| `DecodeAuthorizationMessage` | Descifrar el motivo de un `AccessDenied` codificado |

### Los dos lados de una asunción entre cuentas
1. **Política de confianza del rol destino** (en B): `Principal` = el rol/cuenta de A que puede asumirlo (+ condiciones).
2. **Permiso en el origen** (en A): `sts:AssumeRole` sobre el ARN del rol de B.

Faltando cualquiera de los dos: `AccessDenied`.

### Qué recibes
`AccessKeyId`, `SecretAccessKey`, `SessionToken` y `Expiration`. **Duración:** 1 h por defecto; hasta el máximo del rol (1–12 h). Con **encadenamiento de roles** (asumir un rol desde otro rol asumido) el máximo es **1 h**.

### Piezas que importan
| Pieza | Para qué |
|---|---|
| **Nombre de sesión** | Aparece en CloudTrail: pon el cliente/tenant/persona |
| **ExternalId** | Defensa contra el «delegado confundido» cuando un tercero asume un rol tuyo |
| **Etiquetas de sesión** (`sts:TagSession`) | ABAC dinámico (`proyecto`, `tenant`) |
| **Identidad de origen** (*source identity*) | Atribuir acciones a quien inició la cadena |
| **Condición MFA** | `aws:MultiFactorAuthPresent` en la confianza |
| **Política de sesión** | Recorta aún más esta sesión |
| **Puntos de enlace regionales** | `sts.<región>.amazonaws.com` (el global es heredado) |

### El delegado confundido (ExternalId)
Si un proveedor de SaaS asume roles en las cuentas de sus clientes, un cliente malicioso podría pedirle que asuma el rol de **otro** cliente. Solución: cada cliente debe usar un **ExternalId único y secreto** (generado por el proveedor, no elegido por el cliente) en la confianza del rol.

### Revocar sesiones
No se «quitan» credenciales ya emitidas; se añade una política que **niega** las emitidas antes de cierto momento (`aws:TokenIssueTime`) y se espera a que caduquen (la consola de IAM ofrece «Revocar sesiones activas»).

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Servicio en cuenta A lee un bucket de la cuenta B | `AssumeRole` a un rol de B (o política de bucket + rol) |
| Un SaaS opera en cuentas de clientes | Rol del cliente con **ExternalId** |
| CI/CD despliega en varias cuentas | `AssumeRoleWithWebIdentity` (OIDC) hacia roles de cada cuenta |
| Tu app corre en ECS/EKS/Lambda | **No** asumas manualmente: el rol de la tarea/IRSA ya es una asunción |
| Una app necesita «claves» | **No**: credenciales temporales |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Credenciales temporales** | Tres valores con fecha de caducidad |
| **Sesión** | Lo que dura y hace una asunción |
| **Encadenamiento de roles** | Asumir un rol desde un rol ya asumido (máx. 1 h) |
| **ExternalId** | Secreto compartido contra el delegado confundido |
| **Confianza** | Quién puede asumir el rol |
| **Nombre de sesión** | Etiqueta de auditoría de la asunción |
| **Refresco** | El SDK renueva antes de que caduque |

## 5. Cómo se usa
1. En B: rol con **confianza** a A y permisos mínimos: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. En A: permiso `sts:AssumeRole` sobre el ARN.
3. CLI: perfil con `role_arn` + `source_profile`: [`ejemplos/cli/sts.sh`](ejemplos/cli/sts.sh).
4. Java: `StsAssumeRoleCredentialsProvider` (renueva solo): [uso en Java](uso-en-java.md).
5. Cuando algo falla: `get-caller-identity`, CloudTrail (`AssumeRole`), `decode-authorization-message`.

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Rol origen (A) | `sts:AssumeRole` sobre **ARN concretos** | Lo que el rol destino permita |
| Rol destino (B) | Confianza acotada (principal, `aws:SourceAccount`, ExternalId, MFA) | Permisos mínimos |
| Auditoría | CloudTrail: eventos `AssumeRole*` | — |

- Confía en **un rol concreto**, no en `:root` de la cuenta (a menos que lo necesites y controles).
- Para terceros: **ExternalId obligatorio**.
- Duración mínima suficiente; para humanos con permisos altos, sesión corta.
- Registra y alerta asunciones desde lugares inesperados.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Un rol por propósito y cuenta destino | Un rol «super» al que todos hacen `AssumeRole` |
| `Principal` = rol concreto | `Principal: {"AWS":"*"}` |
| ExternalId único por cliente | ExternalId igual para todos o elegido por el cliente |
| Nombre de sesión informativo | `session1` para todo |
| Dejar que el SDK refresque | Llamar a `AssumeRole` en cada petición |
| STS regional | Depender del endpoint global |
| Sesiones cortas para privilegios altos | 12 h «por comodidad» |

## 8. Límites, costos y versiones
- **Costo:** STS no cobra. Sí existen cuotas de solicitudes por cuenta/región *(verifica)*.
- **Límites:** duración 15 min–12 h según rol (encadenamiento 1 h); tamaño de etiquetas de sesión; tamaño de la política de sesión.
- **Terraform:** `aws_iam_role`, `aws_iam_policy_document`. Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
