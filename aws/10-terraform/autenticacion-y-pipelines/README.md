# AWS · Terraform · Autenticación y pipelines (OIDC)

**Un pipeline que despliega infraestructura necesita un pase, no una llave.** Con la federación OIDC, el sistema de integración continua (aquí GitHub Actions) presenta un token firmado de corta vida, AWS lo valida y entrega credenciales temporales de un rol. **No hay claves de acceso guardadas en ningún secreto.**

## 1. Qué es

**Analogía:** el **pase de visitante de un solo día**. En la puerta no dejas una copia de la llave del edificio: el guardia comprueba quién eres (tu empresa y a qué piso vas) y te da un pase que caduca en una hora y solo abre las puertas de tu piso.

```
 GitHub Actions (repo + entorno/rama) ── token OIDC (JWT firmado) ──► AWS STS
                                              AssumeRoleWithWebIdentity
                          valida: emisor (proveedor OIDC) · audiencia (aud) · sujeto (sub)
                                              │
                                              ▼
                         credenciales temporales (≈ 1 h) del ROL ──► terraform plan / apply
                                              │                              │
                                 estado en S3 (solo su prefijo)     recursos de su componente
```

## 2. Cómo funciona por dentro

| Pieza | Qué hace |
|---|---|
| **Proveedor de identidad OIDC** | Registra en IAM que `token.actions.githubusercontent.com` es un emisor confiable (audiencia `sts.amazonaws.com`) |
| **Token OIDC de GitHub** | Lo emite GitHub por ejecución; contiene `sub` (repositorio y entorno/rama), `aud`, `repo`, `ref`, `environment`… Se pide con `permissions: id-token: write` |
| **Política de confianza del rol** | Dice **quién puede asumir** el rol: `Principal` = el proveedor; `Condition` sobre `aud` y, sobre todo, `sub` |
| **El `sub`** | `repo:org/repo:environment:prod` (ejecución en un entorno protegido), `repo:org/repo:ref:refs/heads/main` (rama), `repo:org/repo:pull_request` (PR). **Es la llave real de seguridad** |
| **Rol de `plan`** | Solo lectura de la infraestructura + lectura del estado + candado: lo asume un PR |
| **Rol de `apply`** | Permisos de cambio acotados al componente; solo lo asume una ejecución en el **entorno protegido** (con aprobación) |
| **Límite de permisos (*permissions boundary*)** | Techo que ningún rol creado por el pipeline puede superar: evita que `apply` se otorgue administrador |
| **Entornos de GitHub** | Reglas de aprobación y ramas permitidas; su nombre viaja en el `sub` |
| **Multicuenta** | El rol del pipeline asume otro rol en la cuenta destino (`assume_role` en el proveedor `aws`) |
| **Puerta de seguridad** | Análisis automático de `terraform show -json plan`: bloquea destrucción de datos, permisos amplios, puertos abiertos |
| **Deriva nocturna** | `plan -detailed-exitcode` programado: avisa de cambios hechos fuera de Terraform |

## 3. Para qué sirve y cuándo NO

| ✅ Sirve para | ❌ No sirve para |
|---|---|
| Pipelines sin secretos de larga vida | Personas (usa [IAM Identity Center](../../02-iam/README.md)) |
| Permisos distintos para `plan` y `apply` | Evitar la revisión humana de cambios de riesgo |
| Auditar quién desplegó qué (CloudTrail registra la federación) | Reemplazar los permisos mínimos del rol (el OIDC solo prueba *quién* es) |
| Entornos con aprobación obligatoria | Ejecuciones desde forks no confiables con permisos de escritura |

## 4. Conceptos clave

| Palabra | Significado simple |
|---|---|
| **OIDC** | Forma estándar de que un sistema demuestre su identidad con un token firmado |
| **JWT / token** | Documento firmado y caduco que dice quién eres |
| **`aud` (audiencia)** | Para quién es el token (`sts.amazonaws.com`) |
| **`sub` (sujeto)** | Quién es exactamente: repositorio + entorno/rama |
| **Política de confianza** | Quién puede asumir el rol |
| **Credenciales temporales** | Acceso que caduca solo (≈ 1 hora) |
| **Entorno protegido** | Entorno de GitHub con aprobadores y ramas permitidas |
| **Plan guardado** | `terraform plan -out`: se aprueba **ese** plan y se aplica **ese** mismo archivo |
| **Deriva** | Diferencia entre el código y lo real por cambios manuales |
| **Límite de permisos** | Techo de permisos para los roles que crea el pipeline |

## 5. Cómo se usa
1. Crea el **proveedor OIDC** y los **roles** (plan y apply, por entorno) con Terraform: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf). Los roles se crean una vez, desde una cuenta administrada de forma manual y revisada.
2. En el repositorio, configura los **entornos** (`dev`, `prod`) con aprobadores y ramas permitidas.
3. Usa el flujo de trabajo de [`ejemplos/github/terraform.yml`](ejemplos/github/terraform.yml): PR → `plan` (rol de lectura) → comentario; `main` → `plan` guardado → puerta → aprobación → `apply` **del mismo plan**.
4. Añade la **puerta de seguridad** que analiza `plan.json` (con `jq` o con el analizador en Java: [uso en Java](uso-en-java.md)).
5. Programa la **deriva nocturna** ([`ejemplos/github/deriva.yml`](ejemplos/github/deriva.yml)).
6. Verifica la confianza de los roles con el validador y con `simulate-principal-policy` ([`ejemplos/cli/oidc.sh`](ejemplos/cli/oidc.sh)).
7. Audita las asunciones con CloudTrail (`AssumeRoleWithWebIdentity`).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **Rol `plan` (PR)** | `ReadOnlyAccess` (o equivalente acotado) | Lee el estado de su prefijo; escribe solo el candado |
| **Rol `apply` (entorno)** | Cambios sobre los servicios de su componente; crear roles **solo con el límite de permisos** | Lee/escribe el estado de su prefijo |
| **Proveedor OIDC** | Lo gestiona el equipo de plataforma | — |
| **Aprobadores del entorno** | Aprueban el `apply` | — |
| **Personas** | Sin credenciales de larga vida del pipeline | — |

- **El `sub` es lo que importa.** Un `sub` con comodín total (`repo:*`) o de toda la organización (`repo:org/*`) permite que **otro repositorio** asuma tu rol de producción. Para `apply`, exige `environment:<nombre>`.
- `StringEquals` **no interpreta** `*` (lo toma literal): para patrones usa `StringLike`.
- Siempre valida `aud` = `sts.amazonaws.com`.
- **Dos roles por entorno**: el PR nunca puede asumir el rol de `apply`.
- Fija las acciones de terceros por *hash* de commit; evita `pull_request_target` con código de PRs externos.
- El rol de `apply` **no debe poder crearse administrador**: límite de permisos + SCP ([Organizations](../../09-gobierno/organizations-scp/README.md)).
- Duración de sesión de 1 hora por defecto: planifica `apply` largos o divídelos por componente.
- Los registros de CloudTrail guardan el `sub`: úsalos para investigar quién desplegó.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| OIDC con credenciales temporales | Claves de acceso de IAM guardadas como secretos del repositorio |
| `sub` exacto por entorno para `apply` | `repo:org/*` o `repo:*` |
| Roles separados para `plan` y `apply` | Un solo rol «de Terraform» con administrador |
| Aplicar el **mismo plan** que se aprobó | Volver a planificar en el `apply` |
| Puerta automática sobre el plan | Aprobar planes sin leerlos |
| `concurrency` sin cancelar los `apply` en curso | Cancelar un `apply` a mitad (deja candado y estado parcial) |
| Límite de permisos para los roles creados | Permitir `iam:*` sin condiciones |
| Deriva nocturna con aviso | Descubrir los cambios manuales en el próximo `apply` |
| Revisar el workflow con el mismo rigor que el código | Dar permisos de escritura de workflows a cualquiera |

## 8. Límites, costos y versiones
- **Costo:** el OIDC y STS no cuestan; pagas los minutos del sistema de integración continua.
- **Límites** *(verifica)*: un proveedor OIDC por emisor y cuenta; duración de sesión del rol entre 1 y 12 horas (con encadenamiento de roles, 1 hora); tamaño de la política de confianza limitado.
- **Los forks** no reciben token OIDC con permisos de escritura por defecto: los PR de forks no pueden planificar contra tu cuenta (es una protección).
- **Acciones de terceros:** `aws-actions/configure-aws-credentials` y `hashicorp/setup-terraform` / `opentofu/setup-opentofu`; usa la versión mayor vigente y fija por *hash* *(verifica)*.
- **Terraform:** `aws_iam_openid_connect_provider`, `aws_iam_role`, `aws_iam_policy`, `aws_iam_role_policy_attachment`. Validado con `init` + `validate`.
- **Java:** analizador de planes (`terraform show -json`), validador de políticas de confianza OIDC, ejecutor aislado de `terraform show`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
