# AWS · 10 Terraform en AWS

Terraform convierte la infraestructura en **código que se revisa, se prueba y se repite**. Este capítulo reúne las tres piezas que lo hacen seguro en AWS: dónde vive su memoria, con qué identidad se ejecuta y cómo se organiza para reutilizarlo.

| Servicio | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Estado remoto](estado-remoto/README.md) | ¿**Dónde** recuerda Terraform lo que construyó? | El libro de obra del edificio | Backend `s3` privado, cifrado con KMS, versionado y con candado nativo; dividir el estado; `moved`, `import`, `removed` |
| [Autenticación y pipelines](autenticacion-y-pipelines/README.md) | ¿**Quién** ejecuta los cambios y con qué permisos? | El pase de visitante de un solo día | Federación OIDC sin secretos, roles de plan y de apply, GitHub Actions, puerta de seguridad, deriva nocturna |
| [Módulos y entornos](modulos-y-entornos/README.md) | ¿**Cómo** reutilizo y organizo el código? | La receta y las cocinas | Módulos versionados y probados, un estado por entorno, migraciones sin destruir |

> Las tres **se apoyan entre sí**: el estado guarda lo que construyeron los pipelines; los pipelines solo funcionan con roles que el estado y los módulos asumen; y los módulos son lo que los pipelines despliegan, entorno por entorno.

## Árbol de decisión: «quiero que…»

```
¿Quiero que el equipo comparta una sola memoria y no se pisen dos apply?
   └─ Estado remoto en S3 con use_lockfile; un estado por entorno y componente

¿Quiero que el pipeline no guarde ninguna clave de acceso?
   └─ Proveedor OIDC + rol con política de confianza de sub exacto

¿Quiero que un PR solo pueda leer y que solo producción aplique tras aprobación?
   └─ Dos roles por entorno (plan: lectura / apply: cambios acotados) + entorno protegido de GitHub

¿Quiero que veinte aplicaciones usen la misma receta segura?
   └─ Módulo versionado (?ref=) + for_each con mapa + pruebas con terraform test

¿Quiero renombrar o reorganizar sin destruir?
   └─ moved (y verificar «0 to destroy» en el plan)

¿Quiero adoptar lo creado a mano?
   └─ import + plan -generate-config-out + plan sin cambios

¿Quiero detectar cambios hechos fuera de Terraform?
   └─ plan nocturno con -detailed-exitcode y aviso (deriva)

¿Quiero impedir que un plan borre la base de datos o abra un puerto al mundo?
   └─ Puerta automática sobre terraform show -json (jq o el analizador en Java) + prevent_destroy

¿Quiero que el pipeline no pueda crearse administrador?
   └─ Límite de permisos en los roles que crea + SCP (capítulo 09)

¿Quiero un portal donde los equipos pidan su servicio?
   └─ Java valida (mismas reglas del módulo) y genera tfvars.json → pull request → pipeline → aprobación (el portal nunca aplica)
```

## Comparativa

| Característica | Estado remoto | Autenticación y pipelines | Módulos y entornos |
|---|---|---|---|
| **Qué resuelve** | Memoria compartida, candado, recuperación | Identidad sin secretos y permisos mínimos | Reutilización, estándares y orden |
| **Dónde vive** | Objetos en un bucket de S3 | Proveedor OIDC, roles y políticas de IAM | Carpetas y repositorios de código |
| **Si falla** | Nadie puede planificar; estado perdido | Los pipelines no entran, o entran con demasiado poder | Cambios inesperados, copias distintas por entorno |
| **Riesgo principal** | El estado contiene secretos | `sub` demasiado amplio; administrador en el pipeline | Módulos sin versión; variables que apagan la seguridad |
| **Se versiona en Git** | No (nunca) | Sí (roles y workflows) | Sí (con etiquetas) |
| **Permisos de datos** | Lectura/escritura del prefijo + KMS | Los roles los reciben de este capítulo | — |
| **Se prueba con** | Simulacro de recuperación | PR de prueba y deriva nocturna | `terraform test` con proveedor simulado |
| **Error típico** | `force-unlock` sin comprobar | Cancelar un `apply` a medias | `count` sobre listas que cambian de orden |

## La receta ModaLima (cómo se ve junto)

| Pieza | Decisión |
|---|---|
| Cuenta de herramientas compartidas | Bucket `modalima-tfstate-…`, KMS propio, política TLS-only y borrado de versiones solo para el administrador |
| Estados | `env/<entorno>/<componente>/terraform.tfstate` (`red`, `datos`, `servicios`) |
| Identidad | Un proveedor OIDC por cuenta; `terraform-plan-<env>` (PR y `main`) y `terraform-apply-<env>` (entorno protegido) |
| Techo de permisos | Política de límite para los roles `app-*` + SCP de protección ([capítulo 09](../09-gobierno/README.md)) |
| Módulos | `servicio-base` (cola + DLQ, logs, rol) con versión `v1.x` y pruebas |
| Pipeline | PR → plan; `main` → plan guardado → puerta → aprobación → apply del mismo plan |
| Deriva | Plan nocturno con aviso al canal de operaciones |
| Autoservicio | Portal en Java que valida y genera `servicios.auto.tfvars.json` (pull request) |

## Orden recomendado de adopción

1. **Estado remoto** en S3 (con candado y versionado) antes de que haya un segundo ingeniero.
2. **Proveedor OIDC y roles de plan/apply** por entorno; elimina las claves de acceso del pipeline.
3. **Un estado por entorno y componente**; permisos por prefijo.
4. **Módulo `servicio-base`** con contrato, pruebas y versión; entornos como carpetas.
5. **Puerta de seguridad** y **deriva nocturna** en el pipeline.
6. **Límite de permisos y SCP** para que el pipeline no se otorgue más poder.
7. **Autoservicio** con validación en Java y prueba de contrato.
8. **Landing zone** repetible para cada cuenta nueva (capítulo 11).

## Reglas transversales

- **El estado es sensible:** cifrado, privado, versionado, sin acceso humano habitual.
- **Sin claves de larga vida** en pipelines: OIDC y credenciales temporales.
- **El `sub` exacto** es la llave real; `apply` exige entorno protegido.
- **Aplica el plan que se aprobó**, no uno nuevo; nunca canceles un `apply` en curso.
- **Versiones fijas:** módulos (`?ref=`), proveedores (`.terraform.lock.hcl`) y Terraform (`required_version`).
- **`for_each` con mapa**, no `count` con listas.
- **Entornos como carpetas**, no como workspaces.
- **Refactoriza con `moved`** y verifica «0 to destroy».
- **El módulo es política:** lo que no debe apagarse no es una variable.
- **El portal valida y propone; el pipeline aplica.**

## Java en Terraform: qué construye cada `uso-en-java.md`

Mismo molde: **núcleo puro** (se prueba sin red), **envoltorio mínimo** y los mismos casos en Spring MVC, WebFlux, Quarkus imperativo y Mutiny.

| Servicio | Qué construyes desde Java | Patrón común |
|---|---|---|
| Estado remoto | Auditor de solo lectura del bucket (versionado, cifrado, acceso público, TLS, candados colgados, claves fuera de convención, historial de versiones) | Reglas puras + traducción compartida con el cliente asíncrono |
| Autenticación y pipelines | Analizador de `terraform show -json` (APROBAR/REVISAR/BLOQUEAR), validador de políticas de confianza OIDC, ejecutor aislado sin credenciales | Falla cerrado + proceso con tiempo y salida acotados |
| Módulos y entornos | Validador espejo de las `validation` del módulo, generador determinista de `tfvars.json`, prueba de contrato | Salida determinista + contrato verificado por `terraform test` |

Reglas comunes: el análisis de CPU va a `boundedElastic` / pool de trabajo en reactivo; ningún servicio de este capítulo **aplica** infraestructura; nada registra el contenido del estado ni de los planes completos.

## Cómo se relaciona con otros capítulos

- [Fundamentos](../00-fundamentos/README.md): cuentas, regiones y la CLI.
- [IAM](../02-iam/README.md): roles, políticas, límites de permisos y federación.
- [Secretos](../03-secretos/README.md): KMS del estado y secretos fuera del código.
- [Storage](../06-storage/README.md): S3, versionado, cifrado y bloqueo de acceso público.
- [Gobierno](../09-gobierno/README.md): SCP que protegen la auditoría y los roles, CloudTrail sobre el bucket del estado, Config y presupuestos.
- [Casos integrados](../11-casos-integrados/README.md): la landing zone y el runbook que usan todo lo anterior.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos (Terraform validado, CLI, JSON, flujos de GitHub), troubleshooting, repaso y prompt de NotebookLM.
