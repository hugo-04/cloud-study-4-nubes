# AWS · 02 IAM

IAM responde en cada llamada: **¿quién eres y qué puedes hacer?** Este capítulo cubre las cuatro piezas que, juntas, dan identidad a **personas**, **aplicaciones**, **otras cuentas** y **pods**.

| Servicio | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Roles y políticas](iam-roles-politicas/README.md) | ¿**Qué puede hacer** cada identidad? | Chaleco con etiqueta de permisos y lista de quién puede ponérselo | Todo: permisos mínimos, confianza, límites, condiciones, ABAC |
| [IAM Identity Center](identity-center/README.md) | ¿Cómo entran las **personas**? | Recepción única con pase del día por edificio | SSO con MFA a muchas cuentas, grupos del directorio, sesiones cortas |
| [STS y asumir roles](sts-asumir-roles/README.md) | ¿Cómo se **cruza de cuenta** o se obtienen credenciales temporales? | Pase de visitante con caducidad | Acceso entre cuentas, terceros con ExternalId, CI/CD, credenciales temporales |
| [IRSA y Pod Identity](irsa-pod-identity/README.md) | ¿Cómo obtiene un **pod** su identidad? | Cada empleado con su pase propio | Permisos por aplicación en EKS (y el patrón de ECS/Lambda/EC2) |

> Se apoyan entre sí: **Identity Center** y **IRSA/Pod Identity** son formas de *llegar* a un rol; **STS** es el mecanismo debajo; **Roles y políticas** definen qué permiten.

## Árbol de decisión: «quiero que…»

```
¿Una PERSONA entra a la consola o a la CLI?
   └─ IAM Identity Center (grupos del directorio + conjunto de permisos + MFA)

¿Una APLICACIÓN en ECS / Lambda / EC2?
   └─ Su rol de tarea / de ejecución / perfil de instancia (nada de claves)

¿Una APLICACIÓN en EKS?
   └─ Pod Identity (o IRSA si es Fargate): un ServiceAccount y un rol por aplicación

¿Un PIPELINE de CI/CD despliega?
   └─ Rol asumible por OIDC (capítulo Terraform), nunca una clave guardada en el CI

¿Una cuenta lee/escribe recursos de OTRA cuenta?
   └─ STS AssumeRole a un rol de la cuenta destino (confianza + permiso en origen),
      o política de recurso con aws:PrincipalOrgID

¿Un TERCERO (SaaS) opera en mi cuenta?
   └─ Rol con ExternalId único generado por el tercero y confianza al rol concreto

¿Quiero limitar lo que un equipo puede darse a sí mismo?
   └─ Límite de permisos (+ SCP en la organización)

¿Una política por proyecto se está multiplicando?
   └─ ABAC: etiquetas en principal y recurso

¿Hay una clave de acceso de larga duración?
   └─ Reemplázala por un rol; si no se puede, rotación + alarma
```

## Comparativa

| Característica | Roles y políticas | Identity Center | STS (AssumeRole) | IRSA | Pod Identity |
|---|---|---|---|---|---|
| **Quién lo usa** | Todos | Personas | Servicios y cuentas | Pods | Pods |
| **Credenciales** | Definen permisos | Temporales vía portal/CLI | Temporales (1–12 h; cadena 1 h) | Temporales vía OIDC | Temporales vía agente |
| **Configuración clave** | Confianza + permisos | Instancia + IdP + asignaciones | Confianza + `sts:AssumeRole` | OIDC + anotación + `sub`/`aud` | Complemento + asociación |
| **Riesgo típico** | `Resource: "*"`, `PassRole` | Admin permanente en prod | Confianza a `:root`, sin ExternalId | Confianza sin `sub` | SDK antiguo / Fargate |
| **Auditoría** | CloudTrail | Registros del portal + CloudTrail | Nombre de sesión | `sub` del token | Etiquetas de sesión |
| **Como código** | `aws_iam_*` | `aws_ssoadmin_*` | `aws_iam_role` | `aws_iam_openid_connect_provider` | `aws_eks_pod_identity_association` |

## La receta ModaLima (cómo se ve junto)

| Quién | Cómo entra | Qué puede |
|---|---|---|
| Equipo de plataforma | Identity Center, grupo `plataforma`, sesión 2 h | Administrador en dev; solo lectura en prod; administrador en prod bajo demanda |
| Desarrolladores de Pedidos | Identity Center, grupo `desarrollo-pedidos` | `Desarrollo` en dev; sin acceso a prod |
| Auditoría | Identity Center, grupo `auditoria` | `SecurityAudit` en todas las cuentas |
| Servicio de pedidos (EKS) | Pod Identity | Leer su cola; escribir su prefijo en S3 |
| Servicio de facturas (Fargate) | IRSA | Escribir `facturas/*` en el bucket |
| Servicio de reportes | Rol de tarea + `AssumeRole` a clientes con ExternalId | Leer logs de cada cliente |
| Pipeline | OIDC → rol por cuenta | Desplegar con permisos acotados |

## Orden recomendado de adopción
1. **Raíz** protegida (MFA, sin claves) y alarmas de uso.
2. **Identity Center** con el directorio de la empresa; grupos y conjuntos de permisos.
3. **Políticas mínimas** y **límite de permisos** para equipos que crean roles.
4. **Roles de carga** (tarea, función, Pod Identity/IRSA); eliminar claves de larga duración.
5. **Acceso entre cuentas** con STS (ExternalId para terceros).
6. **Access Analyzer** y revisiones de permisos sin uso.
7. **Todo como código**; cambios de IAM por pipeline y revisión.

## Reglas transversales
- **Sin claves de larga duración.** Credenciales temporales siempre.
- **Menor privilegio con `Resource` concretos**; condiciones (red, organización, etiquetas, MFA).
- **Un rol por carga de trabajo**, un ServiceAccount por aplicación.
- **Deny explícito** y SCP para las líneas rojas; el límite de permisos para delegar.
- **`iam:PassRole` y `sts:AssumeRole` con ARN concretos.**
- **Asigna a grupos, no a personas.**
- **Todo cambio de IAM pasa por revisión y se registra en CloudTrail.**

## Java en IAM: qué hace cada `uso-en-java.md`

| Servicio | Qué construyes desde Java | Patrón común |
|---|---|---|
| Roles y políticas | Linter de políticas (hallazgos por gravedad) y probador con el simulador de IAM | Funciones puras sobre `Map<String,Object>` |
| Identity Center | Informe «quién tiene qué» + perfil SSO para desarrollo local | Lector paginado + reglas puras |
| STS | Fábrica de clientes por cliente (tenant) con `StsAssumeRoleCredentialsProvider`, ExternalId derivado, catálogo validado | Caché de proveedores + validación de ARN |
| IRSA / Pod Identity | Detección de la fuente de credenciales, `GetCallerIdentity` al arrancar, indicador de salud | Detección pura + verificación cacheada |

Reglas comunes: **cadena por defecto del SDK** (nunca credenciales fijas), clientes creados **una vez**, llamadas administrativas **fuera del camino caliente**, reglas como **funciones puras**, y en reactivo todo lo bloqueante a `boundedElastic` / worker pool.

## Cómo se relacionan con otros capítulos
- [Fundamentos](../00-fundamentos/README.md): cuentas, ARN, regiones.
- [Red](../01-red/README.md): `aws:SourceVpce`, endpoints de STS y de servicios.
- Secretos: políticas de clave KMS y acceso a Secrets Manager.
- Compute: roles de tarea, de función, de nodo.
- Gobierno: SCP, Config y CloudTrail sobre IAM.
- Terraform en AWS: OIDC de pipelines y roles como código.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos (CLI, Terraform, JSON y los específicos de cada servicio), troubleshooting, repaso y prompt de NotebookLM.
