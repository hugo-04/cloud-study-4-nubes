# AWS · Storage · Amazon S3

**S3 (Simple Storage Service) guarda *objetos* (archivos + metadatos) en *buckets*, con durabilidad de 11 nueves y capacidad prácticamente ilimitada.** Es el disco compartido de casi toda arquitectura AWS: archivos de usuarios, backups, logs, sitios estáticos, datos para analítica y el almacén del patrón Claim Check.

## 1. Qué es

**Analogía:** una **bodega gigante con casilleros etiquetados**. No hay carpetas reales: cada objeto tiene una *clave* única (`pedidos/2026/10/16/abc.pdf`) y los «/» son solo parte del nombre (se usan como prefijo para organizar y filtrar).

```
 Bucket "modalima-prod-facturas-us-east-1"      (nombre único global, vive en UNA región)
 ├─ facturas/2026/10/16/f-001.pdf   ← objeto = clave + datos + metadatos + (versiones)
 ├─ facturas/2026/10/16/f-002.pdf
 └─ exportes/clientes.csv
```

- **Objeto:** hasta 5 TiB. **Clave:** hasta 1024 bytes UTF-8.
- **Consistencia:** lectura inmediata tras escritura (fuerte) para objetos y listados.
- **No es un sistema de archivos:** no hay «renombrar» (copias y borras), ni bloqueos, ni append.

## 2. Cómo funciona por dentro

| Pieza | Qué hace |
|---|---|
| **Bucket** | Contenedor de objetos; nombre único en el mundo; configuración propia (cifrado, versiones, ciclo de vida, políticas) |
| **Objeto y clave** | Datos + metadatos; la clave es el identificador completo |
| **Clases de almacenamiento** | Standard, Intelligent-Tiering, Standard-IA, One Zone-IA, Glacier Instant/Flexible/Deep Archive, Express One Zone: más barato guardar = más caro/lento recuperar *(verifica la lista actual)* |
| **Versionado** | Cada PUT crea una versión; borrar pone un *marcador de borrado*; permite recuperar |
| **Ciclo de vida** | Reglas: pasar a otra clase, expirar versiones viejas, abortar cargas multiparte incompletas |
| **Cifrado** | Todo objeto nuevo se cifra (SSE-S3 por defecto); SSE-KMS con tu clave y *Bucket Keys* para reducir llamadas a KMS |
| **Block Public Access** | Cuatro interruptores que impiden acceso público, a nivel de cuenta y de bucket |
| **Propiedad de objetos** | `BucketOwnerEnforced`: las ACL quedan deshabilitadas y manda la política |
| **Carga multiparte** | Archivos grandes en partes paralelas (5 MiB–5 GiB por parte, hasta 10 000 partes) |
| **Checksums** | CRC32, CRC32C, CRC64NVME, SHA-1, SHA-256: S3 valida la integridad de lo subido |
| **Replicación** | Entre buckets de la misma región o de otra (necesita versionado) |
| **Object Lock** | WORM (no se puede borrar/cambiar hasta fecha o por retención legal) |
| **Eventos** | Notificaciones a SQS/SNS/Lambda/EventBridge: [eventos de S3](../eventos-s3/README.md) |
| **Puntos de acceso** | Nombre + política propia para un subconjunto del bucket, por equipo |
| **Escrituras condicionales** | `If-None-Match` / `If-Match` para «crear solo si no existe» o «cambiar solo si no cambió» |

Rendimiento: del orden de 3 500 escrituras y 5 500 lecturas por segundo **por prefijo** *(verifica)*; ya no hace falta aleatorizar prefijos.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Archivos de usuario, PDF, imágenes, video | **S3** |
| Backups, exportes, logs, datos de analítica | **S3** (con ciclo de vida) |
| Sitio estático / SPA | **S3 privado + CloudFront con OAC** ([CloudFront](../../05-ingress-api/cloudfront-waf/README.md)) |
| Subir/descargar sin pasar por tu API | **URLs prefirmadas** ([guía](../urls-prefirmadas/README.md)) |
| Mensajes grandes entre servicios | **Claim Check** ([guía](../claim-check/README.md)) |
| Sistema de archivos compartido POSIX | **No S3**: [EFS](../efs/README.md) |
| Base de datos transaccional, consultas por campos | **No S3**: bases de datos |
| Miles de escrituras diminutas en un mismo objeto | **No**: cada PUT reemplaza el objeto entero |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Bucket** | La bodega; su nombre es único en el mundo |
| **Clave / prefijo** | La «ruta» del objeto; el prefijo sirve para filtrar y para permisos |
| **Versión** | Copia anterior recuperable de un objeto |
| **Marcador de borrado** | «Fingir» el borrado en un bucket con versiones |
| **SSE-S3 / SSE-KMS** | Cifrado con clave de S3 / con tu clave de KMS |
| **Bucket Key** | Reduce llamadas (y costo) a KMS |
| **Política de bucket** | Permisos escritos en el bucket (quién y desde dónde) |
| **OAC** | Permiso para que solo tu CloudFront lea el bucket |
| **Multiparte** | Subir un archivo grande en trozos |
| **ETag** | Huella del objeto (no siempre es su MD5) |
| **Presigned URL** | Enlace temporal firmado con tus permisos |

## 5. Cómo se usa
1. Crea el bucket con Block Public Access, propiedad forzada y cifrado: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Activa el **versionado** y las reglas de **ciclo de vida**: [`ejemplos/json/lifecycle.json`](ejemplos/json/lifecycle.json).
3. Añade una **política de bucket** que niegue HTTP sin TLS: [`ejemplos/json/politica-bucket.json`](ejemplos/json/politica-bucket.json).
4. Dale permisos a la aplicación por **rol de IAM** con el prefijo mínimo.
5. Comandos de ejemplo: [`ejemplos/cli/s3.sh`](ejemplos/cli/s3.sh).
6. Desde Java: [uso-en-java.md](uso-en-java.md).

## 6. Seguridad

| Identidad | Plano de control (administrar el bucket) | Plano de datos (leer/escribir objetos) |
|---|---|---|
| **Aplicación** | — | `s3:GetObject`, `s3:PutObject` sobre `arn:aws:s3:::bucket/prefijo/*`; `s3:ListBucket` con condición de prefijo |
| **Pipeline** | `s3:CreateBucket`, `s3:PutBucketPolicy`, `s3:PutLifecycleConfiguration`… | — |
| **Auditoría** | `s3:GetBucket*` | `s3:GetObject` solo en buckets de logs |
| **CloudFront** | — | `s3:GetObject` vía política con `AWS:SourceArn` de la distribución |

- **Todo privado por defecto:** Block Public Access en la cuenta y en cada bucket.
- **Política de bucket con `aws:SecureTransport` = false → Deny** y TLS mínimo 1.2.
- **KMS:** con SSE-KMS, el rol necesita también `kms:GenerateDataKey` y `kms:Decrypt` ([KMS](../../03-secretos/kms/README.md)).
- **Acceso solo desde tu red:** endpoint de gateway de S3 y condición `aws:SourceVpce` ([Red](../../01-red/README.md)).
- **Datos sensibles:** versionado + Object Lock donde haya requisitos de retención; registros de acceso a datos (CloudTrail data events) para lo crítico.
- Una **ACL pública** o una política con `Principal: "*"` sin condiciones son las dos causas clásicas de filtraciones.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Un bucket por dominio de datos y entorno, con nombre convencional | Un bucket para «todo» |
| Block Public Access + `BucketOwnerEnforced` | Habilitar ACL o políticas públicas «para probar» |
| Versionado en datos importantes + regla de versiones antiguas | Versionado sin expiración (la factura crece sin parar) |
| Regla para abortar multipartes incompletas | Dejar partes huérfanas cobrando |
| SSE-KMS con Bucket Key donde haga falta control de claves | KMS por objeto sin Bucket Key en alto volumen |
| Prefijos con significado (`tenant/año/mes/…`) | Claves con datos personales (aparecen en logs y URLs) |
| Checksums (`SHA-256`) en subidas críticas | Fiarse del ETag como hash |
| Subidas grandes con multiparte / Transfer Manager | Un PUT de varios GB sin reintentos |
| Presigned URLs cortas | Credenciales de larga duración en el navegador |
| Escrituras condicionales para evitar pisarse | «Leer, ver si existe, escribir» sin condición |

## 8. Límites, costos y versiones
- **Costo:** GB-mes por clase, **solicitudes** (PUT/LIST cuestan más que GET), **transferencia a Internet**, recuperación en IA/Glacier, duración mínima de almacenamiento en clases frías, monitoreo de Intelligent-Tiering, llamadas a KMS. Dentro de la misma región hacia EC2/Lambda no hay cobro de transferencia.
- **Límites** *(verifica)*: 5 TiB por objeto, 5 GiB por PUT simple, 10 000 partes, 1024 bytes de clave, 100 buckets por cuenta por defecto (ampliable).
- **Versiones del SDK:** el SDK v2 calcula un checksum por defecto (CRC32) en las subidas; con almacenes compatibles que no lo soporten, configúralo (`requestChecksumCalculation`).
- **Terraform:** `aws_s3_bucket` + recursos separados para cada configuración (provider 6.x). Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
