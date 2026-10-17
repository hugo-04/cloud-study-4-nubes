# AWS · Terraform · Estado remoto (S3)

**El estado de Terraform es su memoria:** un archivo que relaciona cada recurso de tu código con el recurso real en AWS (su identificador). Sin él, Terraform no sabe qué construyó ni qué debe cambiar. En equipo, esa memoria debe vivir **en un lugar compartido, privado, cifrado, versionado y con candado**: un bucket de S3.

## 1. Qué es

**Analogía:** el **libro de obra** de un edificio. Los planos son tu código; el libro de obra anota qué se construyó realmente y dónde. Si se pierde el libro, nadie sabe qué hay detrás de las paredes; si dos capataces lo escriben a la vez, se contradicen.

```
 código (.tf) ──► terraform plan ── compara ──► ESTADO (S3)                ──► AWS real
                                                 env/prod/red/terraform.tfstate
                       apply ──► (candado) env/prod/red/terraform.tfstate.tflock
                          └────► actualiza el estado al terminar
```

## 2. Cómo funciona por dentro

| Pieza | Qué hace |
|---|---|
| **Estado (`terraform.tfstate`)** | JSON con la lista de recursos, sus atributos **(incluidos valores secretos en texto claro)**, el `serial` (se incrementa en cada cambio) y el `lineage` (identidad de esa historia) |
| **Backend `s3`** | Guarda y lee el estado desde un bucket: `bucket`, `key`, `region`, `encrypt`, `kms_key_id`, `use_lockfile` |
| **Bloqueo nativo (`use_lockfile = true`)** | Crea el objeto `<key>.tflock` con una escritura condicional: si ya existe, el segundo `apply` espera o falla. Reemplaza al bloqueo con DynamoDB, que quedó obsoleto *(verifica versión)* |
| **Versionado del bucket** | Cada escritura conserva la versión anterior: así se recupera un estado dañado o borrado |
| **Cifrado con KMS** | El estado contiene secretos: cifrado en reposo con clave propia y permisos separados |
| **Clave del estado** | Convención `env/<entorno>/<componente>/terraform.tfstate`: un estado **por entorno y por componente** |
| **`terraform_remote_state`** | Lee las **salidas** (`output`) de otro estado, en solo lectura |
| **`moved` / `import` / `removed`** | Cirugía declarativa y revisable: renombrar sin destruir, adoptar lo creado a mano, dejar de gestionar sin borrar |
| **`init -migrate-state`** | Mueve el estado de un backend a otro (por ejemplo, de local a S3) |
| **Workspaces** | Varios estados bajo la misma clave base; sirven para pruebas efímeras, **no** para separar `dev` de `prod` |

## 3. Para qué sirve y cuándo NO

| ✅ Sirve para | ❌ No sirve para |
|---|---|
| Que todo el equipo y los pipelines compartan una verdad | Guardar secretos «de forma segura» (el estado los contiene: protégelo, no lo uses de bóveda) |
| Evitar que dos `apply` se pisen (candado) | Reemplazar un inventario de recursos (usa Config) |
| Recuperar tras un error (versionado) | Servir de base de datos de configuración de las aplicaciones |
| Leer salidas entre componentes | Compartir *todo* entre componentes (acopla; comparte lo mínimo) |
| Dividir el riesgo (un estado por componente y entorno) | Un único estado gigante para toda la empresa |

## 4. Conceptos clave

| Palabra | Significado simple |
|---|---|
| **Backend** | El lugar donde Terraform guarda el estado |
| **Candado (lock)** | Marca que dice «alguien está aplicando; espera» |
| **`serial` / `lineage`** | Contador de cambios / identidad de la historia del estado |
| **Deriva (drift)** | Diferencia entre el estado/código y lo que realmente existe (cambios manuales) |
| **Plan / apply** | Ver qué cambiaría / hacerlo |
| **Importar** | Traer al estado un recurso que ya existía |
| **`moved`** | «Este recurso cambió de nombre en el código, no lo destruyas» |
| **`removed`** | «Deja de gestionar esto, pero no lo borres» |
| **Salida (output)** | Valor que un componente publica para otros |
| **Estado parcial** | Un `apply` interrumpido: parte creada, parte no; se arregla con otro `apply` |

## 5. Cómo se usa
1. Crea el bucket del estado **en una cuenta compartida de herramientas** (una sola vez, con un `apply` inicial local): [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Configura el backend en cada componente ([`ejemplos/hcl/backend.tf`](ejemplos/hcl/backend.tf)) y pasa los valores con `-backend-config` ([`backend.hcl.ejemplo`](ejemplos/hcl/backend.hcl.ejemplo)), porque el bloque `backend` no admite variables.
3. `terraform init -migrate-state` para mover el estado local a S3.
4. Un estado por **entorno y componente** (`red`, `datos`, `apps`): cambian a ritmos distintos y con distinto riesgo.
5. Comparte entre componentes solo **salidas** ([`lectura-entre-estados.tf`](ejemplos/hcl/lectura-entre-estados.tf)); para datos de aplicación prefiere Parameter Store.
6. Refactoriza con `moved`, adopta con `import`, suelta con `removed` ([`refactor.tf`](ejemplos/hcl/refactor.tf)).
7. Opera con la CLI ([`ejemplos/cli/estado.sh`](ejemplos/cli/estado.sh)) y audita quién toca el estado ([`ejemplos/sql/athena-estado.sql`](ejemplos/sql/athena-estado.sql)).
8. Audita el bucket desde Java ([uso en Java](uso-en-java.md)).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **Pipeline de `apply`** | Crea/modifica los recursos de *su* componente | `s3:GetObject`, `PutObject`, `DeleteObject` solo en su prefijo (`env/prod/red/*`) + `kms:Decrypt`/`GenerateDataKey` |
| **Pipeline de `plan` (pull request)** | Solo lectura de los recursos | `s3:GetObject` en su prefijo y `PutObject` solo sobre `*.tflock` (para el candado) |
| **Administrador del estado** | Gestiona el bucket y la clave | Único que puede borrar versiones |
| **Personas** | — | **Sin acceso directo** al bucket; solo un rol de emergencia, auditado |
| **Auditoría** | — | Eventos de datos de CloudTrail sobre el bucket del estado |

- **El estado contiene secretos**: bucket privado, bloqueo de acceso público, cifrado con KMS, política que exige TLS y **niega el borrado de versiones** a todos salvo al administrador.
- El prefijo de cada rol limita el **radio de explosión**: el pipeline de `red` no puede leer ni dañar el estado de `datos`.
- Nunca subas `*.tfstate`, `.terraform/` ni `*.tfvars` con secretos a Git.
- Para secretos de aplicación usa [Secrets Manager](../../03-secretos/README.md) y referencias, no valores en el código.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Bucket dedicado, versionado, cifrado con KMS, sin acceso público | Estado local o en el repositorio |
| `use_lockfile = true` | Quitar el candado «porque se queda pegado» |
| Un estado por entorno y componente | Un estado único para todo |
| Permisos por prefijo | Dar `s3:*` sobre todo el bucket al pipeline |
| `moved` para renombrar | Renombrar sin `moved` (destruye y recrea) |
| Verificar «0 to destroy» antes de aprobar | Aprobar planes sin leer las destrucciones |
| Simulacro de recuperación cada trimestre | Descubrir el día del desastre que no sabes restaurar |
| `force-unlock` solo tras confirmar que nadie aplica | `force-unlock` a ciegas |
| Compartir salidas mínimas | Dar a todos lectura de todos los estados |

## 8. Límites, costos y versiones
- **Costo:** almacenamiento de S3 (el estado pesa kilobytes o pocos megabytes), solicitudes y KMS; despreciable frente a un incidente.
- **Versiones:** `use_lockfile` requiere Terraform o OpenTofu 1.10 o superior *(verifica)*. OpenTofu añade cifrado del estado del lado del cliente *(verifica)*.
- **Tamaño práctico:** un plan lento (decenas de minutos) y un estado de decenas de megabytes indican que hay que dividir.
- **Terraform:** `aws_s3_bucket` (+ versioning, SSE-KMS, public access block, lifecycle, policy), `aws_kms_key`, `aws_iam_policy`. Validado con `init` + `validate`.
- **Java:** AWS SDK v2 `s3` para auditar el bucket (versionado, cifrado, política, locks colgados, claves fuera de convención).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
