# AWS · Gobierno · AWS Organizations y políticas de control de servicio (SCP)

**AWS Organizations te permite manejar muchas cuentas de AWS como una sola organización: las agrupas en unidades organizativas (OU), consolidas la facturación y aplicas *barandas* (SCP) que ponen un techo a lo que cualquier identidad de esas cuentas puede hacer, incluso sus administradores.** Una SCP **no concede** permisos: solo recorta lo máximo que se puede conceder.

## 1. Qué es

**Analogía:** el **reglamento del edificio**. Cada cuenta es un departamento con su propio dueño (sus administradores deciden quién entra y qué hace). El reglamento (SCP) dice qué está prohibido en *todo* el edificio, sin importar lo que el dueño permita a sus visitas: «nadie apaga las cámaras» (CloudTrail), «nadie construye fuera de las zonas aprobadas» (regiones). El reglamento no da llaves; solo pone límites.

```
Organización (cuenta de administración: facturación y políticas, SIN cargas de trabajo)
 └─ Raíz
     ├─ OU Seguridad       (cuentas: logs, auditoría)        ← SCP: no tocar trazas ni Config
     ├─ OU Infraestructura (cuenta: red compartida)
     ├─ OU Cargas
     │    ├─ OU Producción (cuentas: tienda, pagos)           ← SCP: solo regiones aprobadas, IMDSv2
     │    └─ OU Desarrollo (cuentas: tienda-dev, pagos-dev)
     └─ OU Sandbox         (cuentas de prueba, con tope de costo)

 Permiso efectivo = (política de identidad IAM)  ∩  (SCP de la raíz) ∩ (SCP de cada OU del camino) ∩ (SCP de la cuenta)
```

## 2. Cómo funciona por dentro

| Concepto | Qué hace |
|---|---|
| **Organización** | El conjunto de cuentas bajo una cuenta de administración (*management account*). Con «todas las funciones» (*all features*) habilita las políticas |
| **Cuenta de administración** | Crea la organización, la factura y administra políticas; **las SCP no la limitan**. No debe alojar cargas de trabajo |
| **Cuenta miembro** | Cualquier otra cuenta; las SCP **sí** aplican a sus usuarios y roles (incluido su usuario raíz) |
| **Raíz y OU** | La raíz contiene OU anidadas (hasta cinco niveles *(verifica)*); una política adjunta a una OU baja a todo lo que contiene |
| **SCP** | Documento tipo política IAM que define el techo de permisos de usuarios y roles de las cuentas afectadas |
| **`FullAWSAccess`** | SCP administrada que permite todo; viene adjunta por defecto en cada nivel |
| **Estrategia de lista de denegación** | Dejas `FullAWSAccess` y agregas `Deny` específicos. **Es la recomendada**: simple y mantenible |
| **Estrategia de lista de permitidos** | Quitas `FullAWSAccess` y permites explícitamente cada servicio en cada nivel. Estricta, pero laboriosa |
| **Evaluación** | Una acción se permite solo si la política de identidad la permite **y** ninguna SCP del camino la deniega (y, con lista de permitidos, cada nivel la permite) |
| **Otros tipos de política** | De recursos (RCP), de etiquetas, de respaldo, declarativas: complementan a las SCP *(verifica los tipos vigentes)* |
| **Acceso de confianza y administrador delegado** | Permiten que servicios (CloudTrail, Config, Security Hub…) operen sobre toda la organización desde una cuenta que no es la de administración |
| **Creación de cuentas** | `CreateAccount` es asíncrono; crea el rol `OrganizationAccountAccessRole` para entrar desde la cuenta de administración |
| **Facturación consolidada** | Una factura para todas; descuentos por volumen compartidos |
| **Qué no limitan las SCP** | Cuenta de administración, roles vinculados a servicios, y acciones que ya no requieren permisos IAM *(verifica la lista vigente)* |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Separar producción, desarrollo y pruebas con aislamiento fuerte | **Varias cuentas** en OU distintas |
| Prohibir regiones no aprobadas, apagar trazas, salir de la organización | **SCP** (lista de denegación) |
| Exigir configuración segura (IMDSv2, cifrado) en toda cuenta | **SCP** con condiciones |
| Un tope de costos por equipo | Una cuenta por equipo + [Budgets](../budgets-costos/README.md) |
| Conceder permisos a una persona o servicio | No: **roles IAM** en cada cuenta ([IAM](../../02-iam/README.md)) |
| Restricciones finas por usuario dentro de una cuenta | No: políticas IAM y límites de permisos |
| Detectar recursos que incumplen reglas | No: [Config](../config-reglas/README.md) (la SCP *previene*, Config *detecta*) |
| Auditar quién hizo qué | No: [CloudTrail](../cloudtrail-auditoria/README.md) |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Baranda (*guardrail*)** | Límite que no se puede saltar desde dentro de la cuenta |
| **Rol de emergencia (*break-glass*)** | Rol excluido de las SCP por condición, solo para recuperarse de un error; muy vigilado |
| **`NotAction` en regiones** | Los servicios globales (IAM, STS, Route 53…) no tienen región: se excluyen de la denegación por región |
| **`aws:RequestedRegion`** | Condición con la región a la que va la llamada |
| **`aws:PrincipalArn`** | Condición con el ARN de quien llama; sirve para excluir el rol de emergencia |
| **Denegación explícita en una SCP** | Mensaje de error que indica que la barrera, no la política del usuario, bloqueó la acción |
| **Cuenta como límite de seguridad** | Lo más fuerte que tiene AWS para aislar: por eso una cuenta por entorno y carga |

## 5. Cómo se usa
1. Diseña las **OU** por función y riesgo (Seguridad, Infraestructura, Cargas/Producción, Cargas/Desarrollo, Sandbox): [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Crea la organización con todas las funciones y **habilita el tipo de política SCP**.
3. Escribe las SCP **como código** y pásalas por un validador antes de aplicar ([uso en Java](uso-en-java.md), `ScpLinter`).
4. **Prueba primero en una OU de ensayo** con una cuenta sandbox; solo después adjunta a Producción.
5. Excluye siempre el **rol de emergencia** por condición, y alarma cada uso (CloudTrail).
6. Adjunta de a una política por vez y revisa los errores `AccessDenied` por SCP en CloudTrail.
7. Revisa la lista de cuentas y OU periódicamente ([`ejemplos/cli/organizations.sh`](ejemplos/cli/organizations.sh)).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **Administración de la organización** (pocas personas, con MFA) | `organizations:*` solo en la cuenta de administración | — |
| **Pipeline de políticas** | `organizations:CreatePolicy`, `UpdatePolicy`, `AttachPolicy`, `DetachPolicy`, `ListPolicies`, `DescribePolicy`, `ListTargetsForPolicy` | — |
| **Lectura/inventario** | `organizations:List*`, `Describe*` | — |
| **Cuentas miembro** | Ninguna sobre Organizations (salvo las que delegue la organización) | — |

- Organizations **no tiene plano de datos**: todo es control.
- **La cuenta de administración es la más sensible**: sin cargas, sin usuarios de uso diario, usuario raíz con MFA, claves de acceso raíz inexistentes.
- Si una SCP te deja sin acceso, **se corrige desde la cuenta de administración** (las SCP no la afectan): por eso se protege tanto.
- Una SCP nueva puede tardar unos minutos en aplicarse *(verifica)*; no hagas varios cambios seguidos sin esperar.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Lista de denegación sobre `FullAWSAccess` | Quitar `FullAWSAccess` sin un plan completo |
| Rol de emergencia excluido por condición y alarmado | `Deny` sobre `*` sin condición ni excepción |
| `NotAction` con servicios globales en la SCP de regiones | Listar solo acciones regionales y romper IAM, STS o Route 53 |
| Probar en una OU de ensayo antes de Producción | Adjuntar directo a la raíz |
| Una cuenta por entorno y por carga | Todo en una cuenta con etiquetas «prod» y «dev» |
| SCP como código, revisadas y validadas | Editar en la consola sin rastro |
| Cuenta de administración sin cargas | Desplegar aplicaciones en la cuenta de administración |
| Usar CloudTrail para ver los rechazos por SCP | Adivinar por qué «el admin no puede» |
| Mantener las SCP pequeñas (límite de tamaño) | Un documento gigante con todo |

## 8. Límites, costos y versiones
- **Costo:** Organizations y las SCP **no cuestan**; pagas lo que las cuentas consumen *(verifica)*.
- **Límites** *(verifica)*: tamaño de una SCP ≈ 5 120 caracteres; número de SCP adjuntas por destino; número de cuentas por defecto (ampliable); profundidad de OU.
- **Terraform:** `aws_organizations_organization`, `aws_organizations_organizational_unit`, `aws_organizations_policy`, `aws_organizations_policy_attachment`, `aws_organizations_account`. Validado con `init` + `validate`.
- **Java:** AWS SDK v2 `organizations` (el servicio es global; región `us-east-1`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
