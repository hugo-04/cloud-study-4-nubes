# AWS · Secretos · AWS KMS (Key Management Service)

**KMS** crea y custodia **claves criptográficas** y hace operaciones con ellas (cifrar, descifrar, firmar) **sin que la clave salga jamás de los módulos de seguridad de AWS**. Es la base del cifrado de S3, EBS, RDS, SQS, Secrets Manager y de tus propios datos.

## 1. Qué es

**Analogía:** una **caja fuerte de banco con ventanilla**. No te dan la llave maestra; llevas el documento a la ventanilla, el empleado lo cifra o descifra *dentro* de la bóveda y te devuelve el resultado. Para documentos grandes, la bóveda te da una **llave desechable** (clave de datos): tú cifras en tu escritorio y le entregas la llave desechable ya **sellada** por la bóveda para que se guarde junto al documento.

```
 Cifrado de sobre (envelope encryption)
   1. App ──GenerateDataKey(alias/pedidos, contexto)──► KMS
   2. KMS devuelve: clave de datos EN CLARO + la MISMA clave CIFRADA con la clave KMS
   3. App cifra el dato (AES-GCM) con la clave en claro y la BORRA de memoria
   4. App guarda:  [clave de datos cifrada][IV][dato cifrado]
   Descifrar:  KMS.Decrypt(clave cifrada, contexto) ─► clave en claro ─► AES-GCM ─► dato
```

## 2. Cómo funciona por dentro

### Tipos de clave (por propietario)
| Tipo | Quién la administra | Para qué |
|---|---|---|
| **Propiedad de AWS** | AWS (invisible) | Cifrado por defecto de algunos servicios, sin control tuyo |
| **Administrada por AWS** (`aws/s3`, `aws/secretsmanager`…) | AWS crea y rota | Comodidad; **no** se puede usar entre cuentas ni editar su política |
| **Administrada por el cliente (CMK)** | Tú: política, rotación, alias, borrado | Control total, acceso entre cuentas, auditoría fina |

### Tipos de clave (por uso)
| Tipo | Detalle |
|---|---|
| **Simétrica** (AES-256-GCM) | La mayoría de los casos: `Encrypt`, `Decrypt`, `GenerateDataKey` |
| **Asimétrica** (RSA, ECC) | Cifrar con la pública fuera de AWS, o **firmar/verificar** (la privada nunca sale) |
| **HMAC** | Códigos de autenticación de mensajes |
| **Multi-región** | Misma clave replicada en varias regiones (recuperación ante desastres, cifrado global) |

### Qué manda: la política de la clave
- Toda clave tiene una **política de clave**: es la **raíz de la autorización**. Sin ella ni IAM sirve.
- Patrón estándar: la política concede a la cuenta (`arn:aws:iam::<cuenta>:root`) para que **IAM** pueda dar permisos, más **administradores** de la clave y **usuarios** de la clave.
- **Concesiones (*grants*):** permisos temporales y acotados que otorgan servicios como EBS o RDS.
- **Alias:** nombre amigable (`alias/pedidos-datos`) que apunta a una clave; puedes cambiarlo de clave sin cambiar el código.

### Contexto de cifrado (*encryption context*)
Pares clave-valor **no secretos** que se vinculan criptográficamente al dato: si no los das iguales al descifrar, falla. Aparecen en **CloudTrail** y sirven en políticas (`kms:EncryptionContext:…`). Úsalos siempre (`{"tenant":"cafe-andino","tabla":"pedidos"}`).

### Rotación y ciclo de vida
- **Rotación automática** de claves simétricas administradas por el cliente (periodo configurable; por defecto anual): la clave sigue siendo la misma lógicamente, KMS conserva el material anterior para descifrar lo viejo.
- **Rotación bajo demanda** disponible.
- **Estados:** `Enabled`, `Disabled`, `PendingDeletion` (espera de **7 a 30 días**) y eliminada. **Borrar una clave destruye los datos cifrados con ella**: prefiere deshabilitar.

### Límites de la API y cómo vivir con ellos
- `Encrypt` directo: máximo **4 KB**. Para más: **cifrado de sobre** (`GenerateDataKey`).
- **Cuotas por segundo** compartidas por región: ráfagas pueden dar `ThrottlingException`. Soluciones: **S3 Bucket Keys**, caché de claves de datos (AWS Encryption SDK), reutilizar la clave de datos por lote.

### Quién usa KMS por ti
S3 (SSE-KMS), EBS, RDS/Aurora, DynamoDB, SQS, SNS, Kinesis, EFS, Secrets Manager, Parameter Store (SecureString), CloudWatch Logs, entre otros. Tú eliges la CMK; el servicio hace las llamadas con tus permisos o con concesiones.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Cifrar buckets, volúmenes, bases | CMK por dominio de datos |
| Cifrar campos sensibles de la aplicación | Cifrado de sobre con `GenerateDataKey` |
| Firmar tokens/documentos | Clave asimétrica de firma |
| Compartir datos cifrados con otra cuenta | CMK + política de clave + IAM |
| Guardar contraseñas de usuarios | **No**: usa hash con sal (Argon2, bcrypt); KMS no es para eso |
| Cifrar a escala de millones de objetos por segundo | Claves de datos cacheadas / Bucket Keys |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **CMK / clave administrada por el cliente** | La clave que tú controlas |
| **Política de clave** | Quién puede administrar y usar la clave |
| **Alias** | Nombre estable que apunta a una clave |
| **Clave de datos** | Llave desechable para cifrar datos grandes |
| **Cifrado de sobre** | Cifrar el dato con una clave de datos y esta con KMS |
| **Contexto de cifrado** | Etiquetas autenticadas, visibles en CloudTrail |
| **Concesión (grant)** | Permiso temporal para un servicio o rol |
| **Ventana de borrado** | 7–30 días para arrepentirse |
| **Clave multi-región** | Réplicas con el mismo material |

## 5. Cómo se usa
1. Una **CMK por dominio de datos y entorno** (`alias/prod-pedidos-datos`), no una global ni una por objeto.
2. Política de clave: raíz de la cuenta + administradores + usuarios con `kms:ViaService`: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
3. **Rotación activada**.
4. La aplicación usa **alias** y siempre **contexto de cifrado**.
5. Operación y auditoría: [`ejemplos/cli/kms.sh`](ejemplos/cli/kms.sh).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Administradores de claves (equipo de seguridad) | `kms:Create*`, `Put*`, `ScheduleKeyDeletion`… **sin** `Encrypt/Decrypt` | — |
| Aplicaciones | — | `kms:GenerateDataKey`, `kms:Decrypt` con condiciones |
| Servicios de AWS | Concesiones | Cifrado/descifrado en tu nombre (`kms:ViaService`) |
| Auditoría | `kms:Describe*`, `List*`, `GetKeyPolicy` | — |

- **Separación de funciones:** quien administra la clave no la usa para descifrar, y viceversa.
- Condiciones útiles: `kms:ViaService`, `kms:EncryptionContext:…`, `aws:PrincipalOrgID`.
- **Endpoint de VPC** de `kms` ([Red](../../01-red/vpc-endpoints-privatelink/README.md)).
- Alarmas ante `ScheduleKeyDeletion`, `DisableKey` y cambios de política.
- La **eliminación** requiere ventana larga y doble confirmación.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| CMK por dominio y entorno, con alias | Una clave para toda la empresa |
| Rotación automática activada | Claves eternas |
| Contexto de cifrado en cada operación | Cifrar sin contexto |
| Separar administradores de usuarios | El mismo rol administra y descifra |
| Cifrado de sobre para datos > 4 KB | Llamar a `Encrypt` con archivos |
| Deshabilitar antes de borrar | `ScheduleKeyDeletion` con 7 días en producción |
| Política de clave acotada | `Principal: *` sin condiciones |
| Monitorear el uso | Descubrir un descifrado ajeno meses después |

## 8. Límites, costos y versiones
- **Costo:** por **clave al mes** (las administradas por el cliente), por **10 000 solicitudes** y las claves asimétricas/HMAC cuestan más; las claves administradas por AWS no cobran mensualidad pero sí solicitudes. *Verifica precios.*
- **Límites** (verifica): 4 KB en `Encrypt`, cuotas de solicitudes por segundo por región, alias por clave, concesiones por clave.
- **Terraform:** `aws_kms_key`, `aws_kms_alias`, `aws_kms_grant`, `aws_kms_key_policy`. Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
