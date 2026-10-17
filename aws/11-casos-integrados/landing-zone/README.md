# AWS · Caso integrado · Landing zone de ModaLima

Una **landing zone** es la base sobre la que nacen todas las cuentas de AWS de la empresa: organizadas, vigiladas, con límites de gasto y con las mismas barandas desde el primer día. Este caso muestra cómo ModaLima crea una cuenta nueva en minutos y **comprueba** cada noche que ninguna se haya salido del carril. Une Organizations, SCP, CloudTrail, Config, Budgets, IAM y Terraform.

## 1. Qué es

**Analogía:** un conjunto de edificios en un barrio planificado. Antes de que llegue el primer inquilino ya hay calles (red sin solapamientos), portería con cámaras (CloudTrail de toda la organización), reglamento (SCP) y medidor de luz por departamento (presupuestos). Construir una cuenta nueva es entregar un departamento ya conectado a todo eso.

```
 Cuenta de administración (solo gobierno; sin cargas)
   └─ Organización ─ Raíz (SCP: no apagar auditoría, no salir de la organización)
        ├─ Seguridad ........ cuenta de archivo de logs · cuenta de auditoría
        ├─ Infraestructura .. red compartida · herramientas
        ├─ Cargas (SCP: solo regiones aprobadas)
        │     ├─ Prod ........ pagos-prod · catalogo-prod …
        │     └─ NoProd ...... pagos-dev · pagos-stg …
        └─ Sandbox .......... cuentas de prueba con presupuesto mínimo
 Cada cuenta nueva = solicitud (PR) → validación → CIDR único → cuenta + etiquetas + presupuesto → verificación nocturna
```

## 2. Cómo funciona por dentro

| # | Paso | Detalle que importa |
|---|---|---|
| 1 | Un equipo solicita una cuenta | Carga, entorno, equipo, centro de costos, presupuesto, tamaño de red |
| 2 | Se valida y se planifica | Nombre `{carga}-{entorno}`, correo alias, OU según entorno, CIDR libre y sin solapar |
| 3 | Se crea la cuenta | `CreateAccount` es **asíncrono** (se consulta su estado) y casi irreversible |
| 4 | Heredan las barandas | Los SCP de la raíz y de la OU aplican desde el primer segundo |
| 5 | El trail de la organización la cubre | Un solo trail multirregión hacia la cuenta de logs |
| 6 | Presupuesto y etiquetas | Presupuesto mensual filtrado por cuenta; etiquetas de equipo y costos |
| 7 | Cada noche se verifica la línea base | Trail, Config, presupuesto y cifrado de EBS por defecto; etiquetas; ubicación en la OU correcta |
| 8 | Lo que no cumple, se reporta | Con gravedad y qué hacer; «no se pudo verificar» **también** es un hallazgo |

| Necesidad | Servicio | Capítulo |
|---|---|---|
| Cuentas y OU | Organizations | [09](../../09-gobierno/organizations-scp/README.md) |
| Barandas | SCP | [09](../../09-gobierno/organizations-scp/README.md) |
| Auditoría de toda la organización | CloudTrail | [09](../../09-gobierno/cloudtrail-auditoria/README.md) |
| Reglas de cumplimiento | Config | [09](../../09-gobierno/config-reglas/README.md) |
| Presupuestos | Budgets | [09](../../09-gobierno/budgets-costos/README.md) |
| Acceso de personas | IAM Identity Center | [02](../../02-iam/identity-center/README.md) |
| Cuentas y roles de verificación | STS (asumir roles) | [02](../../02-iam/sts-asumir-roles/README.md) |
| Red sin solapamientos | VPC y CIDR | [01](../../01-red/vpc-subredes/README.md) |
| Todo como código | Terraform | [10](../../10-terraform/README.md) |

### Las tres decisiones que definen el caso
1. **La cuenta es la frontera.** Una cuenta por carga y entorno: el radio de una equivocación es una cuenta, no la empresa.
2. **Barandas preventivas (SCP) + verificación detectiva.** Los SCP impiden; la verificación nocturna descubre lo que se coló o dejó de funcionar.
3. **Nada de CIDR a mano.** El asignador reparte bloques alineados y rechaza solapamientos; así las redes podrán conectarse mañana.

## 3. Para qué sirve y cuándo NO

- **Sirve** para: más de unas pocas cuentas, varios equipos, requisitos de auditoría y control de costos.
- **No** hace falta para: un prototipo en una sola cuenta. Pero **sí** conviene ordenar desde el principio con dos cuentas (administración y una de carga): migrar luego es doloroso.

## 4. Conceptos clave (en palabras simples)

- **Organización / OU:** el árbol de cuentas y carpetas.
- **SCP (política de control de servicios):** techo de permisos para una cuenta u OU; no concede, solo limita.
- **Cuenta de administración:** la que crea la organización; no debe alojar cargas.
- **Trail de organización:** un CloudTrail que registra a todas las cuentas.
- **Línea base:** lo mínimo que toda cuenta debe tener.
- **CIDR:** bloque de direcciones IP de una red (`10.20.16.0/20`).
- **Vending de cuentas:** entregar cuentas nuevas por un proceso repetible.

## 5. Cómo se usa

1. Define la estructura y barandas con [`ejemplos/terraform`](ejemplos/terraform/main.tf) (en la cuenta de administración).
2. Una cuenta nueva = una entrada en el mapa `cuentas` ([ejemplo](ejemplos/json/cuentas.auto.tfvars.json)) por pull request.
3. El asignador de CIDR de [uso en Java](uso-en-java.md) propone el bloque libre y valida el plan.
4. La verificación nocturna produce el informe; las alarmas avisan.
5. Consulta con [`ejemplos/cli/operacion.sh`](ejemplos/cli/operacion.sh).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Pipeline de Terraform (cuenta de administración) | Organizations, SCP, trail, presupuestos | — |
| Servicio de vending (rol de tarea) | `organizations:CreateAccount`, `DescribeCreateAccountStatus`, `ListAccounts`, `ListParents`, `ListTagsForResource` | — |
| Verificador (rol de tarea) | `sts:AssumeRole` hacia `modalima-auditor` de cada cuenta | Rol de solo lectura en cada cuenta: `cloudtrail:DescribeTrails`, `config:Describe*`, `budgets:Describe*`, `ec2:GetEbsEncryptionByDefault` |
| Personas | — | IAM Identity Center con permisos mínimos por cuenta (nada de usuarios IAM) |

- La cuenta de administración **no** ejecuta cargas ni tiene usuarios de trabajo.
- Las cuentas se crean con un rol de acceso inicial que se sustituye por Identity Center.
- El rol `modalima-auditor` de cada cuenta confía solo en el rol del verificador y es de solo lectura.

## 7. Qué hacer / qué NO hacer

| Haz | No hagas |
|---|---|
| Una cuenta por carga y entorno | Todo en una cuenta «porque es más fácil» |
| Barandas en la raíz y en las OU | Confiar en que cada equipo configure bien |
| `prevent_destroy` y `close_on_deletion = false` en cuentas | Dejar que `terraform destroy` toque cuentas |
| Asignar CIDR con herramienta | Escoger rangos «al ojo» |
| Tratar «no se pudo verificar» como hallazgo | Ignorar silenciosamente lo que no responde |
| Correos alias únicos por cuenta | Reutilizar un correo personal |
| Probar los SCP en una OU de pruebas | Aplicar un SCP nuevo directo a producción |
| Presupuestos y etiquetas desde el primer día | Descubrir el gasto a fin de mes |

## 8. Límites, costos y versiones

- Hay un límite de cuentas por organización y un ritmo de creación *(verifica; se puede ampliar)*.
- Cerrar una cuenta tiene condiciones y un periodo de posclausura: planifica como si no se pudiera deshacer.
- Organizations, SCP y presupuestos básicos no tienen costo directo; el trail de la organización y Config cobran por uso *(verifica precios)*.
- Versiones del código: Java 21, Spring Boot 4.1.x, Quarkus 3.40.x, AWS SDK v2; Terraform ≥ 1.5 / OpenTofu con proveedor AWS ~> 6.0.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
