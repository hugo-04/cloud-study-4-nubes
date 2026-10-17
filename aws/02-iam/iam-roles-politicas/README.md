# AWS · IAM · Roles y políticas

**IAM** (Identity and Access Management) responde dos preguntas en cada llamada a AWS: **¿quién eres?** (autenticación) y **¿qué puedes hacer?** (autorización). Todo lo demás —S3, SQS, Lambda, EKS— depende de acertar aquí.

## 1. Qué es

**Analogía:** un edificio con credenciales. El **rol** es un *chaleco de trabajo* que cualquiera autorizado puede ponerse un rato (y devolver); la **política de permisos** es lo que dice la etiqueta del chaleco («puede abrir la bodega 3»); la **política de confianza** es la lista de quién tiene derecho a ponérselo; el **límite de permisos** es un tope que nadie puede superar aunque el chaleco diga más.

```
 identidad (usuario/rol/servicio)
        │  llama: s3:GetObject sobre arn:aws:s3:::modalima-datos/pedidos/1.json
        ▼
   ¿algún DENY explícito?  ──sí──► DENEGADO
        │no
   ¿lo permite la organización (SCP)?  ──no──► DENEGADO
        │sí
   ¿lo permite el límite de permisos / política de sesión (si existen)?  ──no──► DENEGADO
        │sí
   ¿una política de identidad o de recurso lo permite?  ──no──► DENEGADO (por defecto)
        │sí
     PERMITIDO
```

## 2. Cómo funciona por dentro

### Las identidades
| Identidad | Qué es | Cuándo |
|---|---|---|
| **Usuario raíz** | La cuenta misma, con poder total | Solo para tareas que lo exigen; con MFA y sin claves |
| **Usuario IAM** | Credencial de larga duración | Evítalo: usa Identity Center y roles |
| **Grupo IAM** | Conjunto de usuarios IAM | Solo para usuarios IAM (hoy casi nunca) |
| **Rol IAM** | Identidad **temporal**, sin contraseña, que se «asume» | Aplicaciones, personas por SSO, otras cuentas, servicios |
| **Principal de servicio** | `lambda.amazonaws.com`, `ecs-tasks.amazonaws.com`… | Quien puede asumir un rol de servicio |

### Los tipos de política
| Política | Dónde vive | Para qué |
|---|---|---|
| **Basada en identidad** | Pegada a un rol/usuario/grupo | «Esta identidad puede hacer X» (la más común) |
| **Basada en recurso** | En el recurso (bucket, cola, clave KMS, rol) | «Este recurso acepta a Y» (incluye entre cuentas) |
| **Política de confianza** | Dentro de un rol | Quién puede asumir el rol |
| **Límite de permisos** (*permissions boundary*) | Pegado a un rol/usuario | Tope máximo de permisos |
| **SCP** (Organizations) | En la organización/OU/cuenta | Tope por cuenta (capítulo de gobierno) |
| **Política de sesión** | Al asumir el rol | Recorta esa sesión |
| **Políticas administradas** | Compartidas (de AWS o propias) | Reutilizar; evita copiar JSON |
| **En línea** (*inline*) | Incrustada en una identidad | Uno a uno, estrictamente ligada |

### Anatomía de una política
```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Sid": "LeerPedidos",
    "Effect": "Allow",
    "Action": ["s3:GetObject"],
    "Resource": "arn:aws:s3:::modalima-datos/pedidos/*",
    "Condition": { "StringEquals": { "aws:SourceVpce": "vpce-0123456789abcdef0" } }
  }]
}
```
- **Effect:** `Allow` o `Deny`.
- **Action:** `servicio:Acción` (acepta comodines; evítalos).
- **Resource:** ARN(s) afectados.
- **Principal:** solo en políticas de recurso y de confianza.
- **Condition:** cuándo aplica (red, etiquetas, MFA, hora, organización…).
- `NotAction`, `NotResource`, `NotPrincipal`: potentes y peligrosos; evítalos.

### Cómo se decide (lógica de evaluación)
1. **Todo está denegado por defecto.**
2. Un `Deny` explícito en cualquier política **gana siempre**.
3. SCP, límite de permisos y política de sesión actúan como **intersección** (deben permitir).
4. Una política de identidad o de recurso debe **permitir**. Dentro de la misma cuenta basta una de ellas; **entre cuentas deben permitir ambas** (la identidad y el recurso).
5. Las claves KMS exigen que la **política de la clave** lo habilite.

### Condiciones que más se usan
| Clave | Ejemplo |
|---|---|
| `aws:PrincipalOrgID` | Solo identidades de mi organización |
| `aws:SourceVpce` / `aws:SourceVpc` | Solo por mi endpoint/VPC |
| `aws:MultiFactorAuthPresent` | Exigir MFA para acciones sensibles |
| `aws:RequestTag/…` y `aws:ResourceTag/…` | Control de acceso por etiquetas (ABAC) |
| `aws:SecureTransport` | Negar si no es HTTPS |
| `aws:RequestedRegion` | Limitar regiones |
| `sts:ExternalId` | Terceros que asumen un rol |

### ABAC (control por etiquetas)
En vez de una política por proyecto: «puede tocar los recursos cuya etiqueta `proyecto` coincide con **su** etiqueta `proyecto`». Menos políticas, más escala.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Una aplicación en ECS/EKS/Lambda necesita leer una cola | **Rol** con política mínima (no claves) |
| Una persona entra a la consola | Identity Center (servicio siguiente) |
| Otra cuenta necesita leer un bucket | Política de recurso **y** rol asumible |
| Un pipeline despliega infraestructura | Rol asumible por OIDC (capítulo Terraform) |
| «Que sea administrador por si acaso» | **No**: puntúa mal y se paga en incidentes |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **ARN** | Identificador único de un recurso: `arn:aws:s3:::bucket/clave` |
| **Principal** | Quien actúa (usuario, rol, servicio, cuenta) |
| **Asumir un rol** | Recibir credenciales temporales de ese rol |
| **Menor privilegio** | Solo lo necesario, en los recursos necesarios |
| **Deny explícito** | Prohibición que nadie puede levantar con un Allow |
| **Límite de permisos** | Techo para lo que puede dar un rol |
| **Access Analyzer** | Detecta accesos externos y permisos sin uso |
| **Credenciales de larga duración** | Las claves de acceso: el riesgo a eliminar |

## 5. Cómo se usa
1. **Raíz:** MFA, sin claves de acceso, correo de equipo.
2. Un **rol por carga de trabajo** (no uno por entorno compartido): [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
3. Políticas con **recursos concretos** y condiciones ([`ejemplos/json/`](ejemplos/json/)).
4. **Límite de permisos** para equipos que crean sus propios roles.
5. **Access Analyzer** activo; revisión de permisos sin uso.
6. Pruebas con el simulador: [`ejemplos/cli/iam.sh`](ejemplos/cli/iam.sh).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Pipeline de IAM (cuenta de seguridad) | `iam:CreateRole`, `PutRolePolicy`… acotado con **límite de permisos** | — |
| Desarrolladores | Solo lectura (`iam:Get*`, `List*`) | — |
| Aplicaciones | — | Las acciones de **su** política |
| Auditoría | `iam:Get*`, `List*`, Access Analyzer | — |

- **Escalada de privilegios:** `iam:PassRole`, `iam:CreateAccessKey`, `iam:AttachRolePolicy`, `sts:AssumeRole` sobre roles poderosos son equivalentes a «ser administrador». Acótalos con condiciones y límites.
- `iam:PassRole` siempre con **un recurso concreto** y la condición `iam:PassedToService`.
- Sin claves de acceso de larga duración; si existen, rotación y alarma.
- CloudTrail activo para ver quién hizo qué.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Roles con credenciales temporales | Claves de acceso en variables de entorno o en el código |
| `Resource` con ARN concretos | `"Action": "*"`, `"Resource": "*"` |
| Condiciones (red, organización, etiquetas) | Confiar solo en el nombre del rol |
| Límite de permisos para delegar | Dar `iam:*` a un equipo «de confianza» |
| Un rol por carga de trabajo | Un rol «de la aplicación» para 30 servicios |
| Revisar permisos sin uso | Acumular permisos «por si acaso» |
| Políticas administradas por el cliente versionadas en Git | Editar políticas a mano en la consola |

## 8. Límites, costos y versiones
- **Costo:** IAM no cobra. Access Analyzer: el análisis de acceso externo es gratuito; el de **acceso no usado** se cobra *(verifica)*.
- **Límites típicos** (verifica): tamaño de política (~6 144 caracteres en políticas administradas), políticas por rol (10 administradas por defecto), roles por cuenta, duración de sesión (1–12 h).
- **Terraform:** `aws_iam_role`, `aws_iam_policy`, `aws_iam_role_policy_attachment`, `aws_iam_policy_document`, `aws_accessanalyzer_analyzer`. Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
