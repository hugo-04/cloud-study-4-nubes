# 07 · Storage de objetos, SAS tokens y patrón Claim Check

**Azure Blob Storage** y sus equivalentes: **AWS S3**, **OCI Object Storage** y **GCP Cloud Storage**. Incluye el acceso temporal por URL en las 4 nubes (**SAS**, **Presigned URL**, **PAR** y **Signed URL**), con permisos de **lectura** y **escritura**, y el patrón de enviar la **URL del archivo por una cola** (*Claim Check*).

---

## 1. Qué es (con analogía)

Una **bodega con casilleros**.

| En la bodega | En la nube |
|---|---|
| El edificio | Cuenta de storage / namespace / proyecto |
| Un estante con nombre | Contenedor / bucket |
| Una caja dentro del estante | Blob / objeto |
| Pasillos (`2026/10/foto.jpg`) | "Carpetas" virtuales: solo son prefijos en el nombre |
| **Una llave que abre un solo casillero y caduca en 15 minutos** | **SAS / Presigned URL / PAR / Signed URL** |

> Un storage de objetos **no es un disco**: no se edita una parte de un archivo; se sube o se reemplaza el objeto completo.

---

## 2. Para qué sirve y cuándo NO usarlo

**Sirve para:** imágenes, documentos, videos, respaldos, logs, datos para analítica, sitios estáticos, archivos que suben los usuarios.

**Cuándo NO usarlo**
- Como **base de datos** (consultas, transacciones): usa una BD.
- Para **archivos que cambian por pedazos** a cada segundo: usa un disco o un servicio de archivos.
- Para **mensajes pequeños de alta frecuencia**: usa una cola o un stream (módulo 08).

---

## 3. Conceptos clave

| Término | Definición simple |
|---|---|
| **Cuenta / bucket** | El contenedor de más alto nivel (Azure: cuenta + contenedor; AWS/GCP: bucket; OCI: bucket dentro de un namespace) |
| **Objeto / blob** | El archivo y sus metadatos |
| **Prefijo** | Parte inicial del nombre, usada como "carpeta" |
| **Tier / clase** | Costo según frecuencia de acceso (caliente, frío, archivo) |
| **Redundancia** | Cuántas copias y dónde (zonas, regiones) |
| **Versionado** | Conserva versiones anteriores |
| **Soft delete** | Lo borrado se puede recuperar un tiempo |
| **Ciclo de vida** | Reglas automáticas: mover a frío o borrar |
| **Inmutabilidad (WORM)** | Impedir modificar o borrar por un tiempo |
| **URL temporal firmada** | Enlace que da acceso limitado y con vencimiento |

---

## 4. Equivalencias en las 4 nubes

| Concepto | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| Servicio | Blob Storage | S3 | Object Storage | Cloud Storage |
| Unidad | Cuenta → contenedor → blob | Bucket → objeto | Namespace → bucket → objeto | Bucket → objeto |
| Tier caliente | Hot | Standard | Standard | Standard |
| Tier poco frecuente | Cool / Cold | Standard-IA / One Zone-IA | Infrequent Access | Nearline / Coldline |
| Archivo | Archive | Glacier (varias clases) | Archive | Archive |
| Redundancia | LRS / ZRS / GRS / GZRS | Multi-AZ por defecto; replicación entre regiones | Replicado entre dominios; replicación entre regiones | Regional / dual-region / multi-region |
| Versionado | Versioning | Versioning | Versioning | Object Versioning |
| Ciclo de vida | Lifecycle management | Lifecycle rules | Lifecycle policies | Object Lifecycle Management |
| Eventos | Event Grid | S3 Event Notifications / EventBridge | Events service | Pub/Sub notifications / Eventarc |
| Acceso temporal por URL | **SAS** | **Presigned URL** | **PAR** | **Signed URL** |
| Acceso privado | Private Endpoint | Interface/Gateway Endpoint | Private Endpoint / Service Gateway | Private Service Connect / Private Google Access |
| Cifrado con claves propias | CMK (Key Vault) | SSE-KMS | Vault | CMEK (Cloud KMS) |
| Sitio estático | Static website | S3 static website | Bucket público + dominio | Bucket + balanceador/CDN |

---

## 5. Azure Blob Storage en detalle

### 5.1 Crear una cuenta segura

```bash
RG=rg-estudio-storage
ST=stmodalimaestudio01      # único global, 3-24 caracteres, minúsculas y números

az group create -n $RG -l eastus2

az storage account create -g $RG -n $ST -l eastus2 \
  --sku Standard_LRS --kind StorageV2 \
  --allow-blob-public-access false \
  --min-tls-version TLS1_2 \
  --https-only true

az storage container create --account-name $ST -n fotos    --auth-mode login
az storage container create --account-name $ST -n subidas  --auth-mode login

az storage blob upload --account-name $ST -c fotos \
  -f foto.jpg -n 2026/10/foto.jpg --auth-mode login
```

Controles de seguridad recomendados:

| Control | Para qué |
|---|---|
| `allow-blob-public-access false` | Que ningún contenedor pueda ser público |
| `min-tls-version TLS1_2` y `https-only` | Solo cifrado en tránsito |
| Deshabilitar **clave compartida** (`--allow-shared-key-access false`) | Obliga a usar Entra ID y SAS de delegación de usuario |
| `public-network-access Disabled` + Private Endpoint | Solo acceso privado (módulo 02) |
| Soft delete + versionado | Recuperar de borrados |
| Defender for Storage | Detectar malware y accesos anómalos |

### 5.2 Redundancia (Azure)

| Sigla | Qué significa | Cuándo |
|---|---|---|
| **LRS** | 3 copias en un solo data center | Datos reproducibles, dev |
| **ZRS** | 3 copias en 3 zonas | Producción típica |
| **GRS / GZRS** | Copia a otra región (con o sin zonas) | Recuperación ante desastres |
| **RA-** | Lectura en la región secundaria | Lectura aun si cae la primaria |

### 5.3 Ciclo de vida

```json
{
  "rules": [{
    "enabled": true,
    "name": "enfriar-y-borrar-logs",
    "type": "Lifecycle",
    "definition": {
      "filters": { "blobTypes": ["blockBlob"], "prefixMatch": ["logs/"] },
      "actions": {
        "baseBlob": {
          "tierToCool":    { "daysAfterModificationGreaterThan": 30 },
          "tierToArchive": { "daysAfterModificationGreaterThan": 180 },
          "delete":        { "daysAfterModificationGreaterThan": 730 }
        }
      }
    }
  }]
}
```
```bash
az storage account management-policy create -g $RG --account-name $ST --policy @politica.json
```

### 5.4 Cómo se autoriza el acceso (de mejor a peor)

| Método | Nota |
|---|---|
| **Entra ID + RBAC** (identidad administrada) | **El preferido** para aplicaciones |
| **SAS de delegación de usuario** | Mejor opción para dar acceso **temporal** a terceros |
| SAS de servicio / de cuenta (firmadas con la clave) | Solo si no hay alternativa |
| Clave de cuenta | **Evitar**: da control total |
| Acceso anónimo | Solo para contenido realmente público |

---

## 6. SAS tokens en Azure

### 6.1 Qué es

Un **Shared Access Signature** es un **token firmado** que se agrega a la URL del recurso y concede **acceso delegado, limitado y con vencimiento**, sin compartir tu identidad ni tus claves.

```
https://stmodalimaestudio01.blob.core.windows.net/fotos/2026/10/foto.jpg
  ?sv=2022-11-02
  &st=2026-10-16T16:00:00Z
  &se=2026-10-16T16:15:00Z
  &sr=b
  &sp=r
  &spr=https
  &sig=FIRMA_DE_EJEMPLO
```

| Parámetro | Significado |
|---|---|
| `sv` | Versión del servicio |
| `st` | Inicio de validez (opcional) |
| `se` | **Fin de validez** (expiración) |
| `sr` | Recurso: `b` blob, `c` contenedor, `d` directorio |
| `sp` | **Permisos** (ver tabla) |
| `spr` | Protocolo permitido (`https`) |
| `sip` | Rango de IP permitido (opcional) |
| `sig` | La firma (no la modifiques: invalida todo) |
| `skoid`, `sktid`, `skt`, `ske`… | Presentes en las SAS de **delegación de usuario** (identifican la clave de delegación) |

### 6.2 Tres tipos

| Tipo | Se firma con | Alcance | Recomendación |
|---|---|---|---|
| **User delegation SAS** | Credenciales de **Entra ID** (clave de delegación) | Blob (y Data Lake) | **La recomendada** |
| **Service SAS** | Clave de la cuenta | Un recurso de un servicio (blob, cola…) | Con política de acceso almacenada, si es necesario |
| **Account SAS** | Clave de la cuenta | Varios servicios | Evitar |

**Política de acceso almacenada (stored access policy):** una política guardada en el contenedor que define permisos y vencimiento; las SAS de servicio pueden referirla y se **revocan borrando o editando la política**.

### 6.3 Permisos: qué significa READ y WRITE

| Letra | Permiso | Para qué |
|---|---|---|
| **`r`** | **Read** | **Descargar** el contenido |
| **`c`** | Create | Crear un blob nuevo |
| **`w`** | **Write** | **Escribir / reemplazar** contenido de un blob |
| `a` | Add | Agregar bloques a un *append blob* |
| `d` | Delete | Borrar |
| `l` | List | Listar blobs (SAS de contenedor) |
| `t` | Tags | Leer/escribir etiquetas |

**Combinaciones habituales**

| Necesidad | Permisos |
|---|---|
| Que el cliente **descargue** un archivo | `r` |
| Que el cliente **suba un archivo nuevo** | `cw` |
| Que el cliente **reemplace** un archivo existente | `w` |
| Que el cliente **liste** una carpeta | `l` (SAS de contenedor) |
| Borrado desde el cliente | `d` (**evítalo**: que borre el backend) |

> Para subir un blob nuevo con una SAS de **un solo blob**, se suelen necesitar `c` y `w`.

### 6.4 Generarla con CLI (delegación de usuario)

```bash
# LECTURA de un blob durante 15 minutos
az storage blob generate-sas --account-name $ST -c fotos -n 2026/10/foto.jpg \
  --permissions r --https-only \
  --expiry $(date -u -d "+15 minutes" '+%Y-%m-%dT%H:%MZ') \
  --auth-mode login --as-user --full-uri

# ESCRITURA (subida de un blob nuevo) durante 15 minutos
az storage blob generate-sas --account-name $ST -c subidas -n entrada/pedido-123.pdf \
  --permissions cw --https-only \
  --expiry $(date -u -d "+15 minutes" '+%Y-%m-%dT%H:%MZ') \
  --auth-mode login --as-user --full-uri
```
> `date -d` funciona en Linux; en macOS usa `date -u -v+15M '+%Y-%m-%dT%H:%MZ'`.

### 6.5 Usarla (curl)

```bash
# Descargar
curl -o foto.jpg "$URL_SAS_LECTURA"

# Subir (el encabezado x-ms-blob-type es obligatorio)
curl -X PUT \
  -H "x-ms-blob-type: BlockBlob" \
  -H "Content-Type: application/pdf" \
  --data-binary @pedido-123.pdf \
  "$URL_SAS_ESCRITURA"
```

### 6.6 Generarla en Java (delegación de usuario)

```java
BlobServiceClient servicio = new BlobServiceClientBuilder()
    .endpoint("https://stmodalimaestudio01.blob.core.windows.net")
    .credential(new DefaultAzureCredentialBuilder().build())
    .buildClient();

OffsetDateTime ahora = OffsetDateTime.now(ZoneOffset.UTC);
UserDelegationKey llave =
    servicio.getUserDelegationKey(ahora.minusMinutes(5), ahora.plusHours(1));

// ---- LECTURA durante 15 minutos ----
BlobClient fotoBlob = servicio.getBlobContainerClient("fotos")
                              .getBlobClient("2026/10/foto.jpg");

BlobServiceSasSignatureValues lectura = new BlobServiceSasSignatureValues(
        ahora.plusMinutes(15),
        new BlobSasPermission().setReadPermission(true))
    .setProtocol(SasProtocol.HTTPS_ONLY);

String urlLectura = fotoBlob.getBlobUrl() + "?"
    + fotoBlob.generateUserDelegationSas(lectura, llave);

// ---- ESCRITURA (blob nuevo) durante 15 minutos ----
BlobClient subidaBlob = servicio.getBlobContainerClient("subidas")
                                .getBlobClient("entrada/" + UUID.randomUUID() + ".pdf");

BlobServiceSasSignatureValues escritura = new BlobServiceSasSignatureValues(
        ahora.plusMinutes(15),
        new BlobSasPermission().setCreatePermission(true).setWritePermission(true))
    .setProtocol(SasProtocol.HTTPS_ONLY);

String urlEscritura = subidaBlob.getBlobUrl() + "?"
    + subidaBlob.generateUserDelegationSas(escritura, llave);
```

**Permisos que necesita quien genera la SAS** (la identidad del backend):
- **Storage Blob Delegator** (para pedir la clave de delegación), **y**
- un rol de **datos** sobre lo que va a compartir (por ejemplo *Storage Blob Data Contributor*): la SAS **no puede dar más permisos de los que tiene quien la firma**.

### 6.7 Revocar

| Si firmaste con... | Para revocar |
|---|---|
| Clave de delegación de usuario | `az storage account revoke-delegation-keys -g $RG -n $ST` (invalida todas las SAS de delegación vigentes) |
| Política de acceso almacenada | Editar o borrar la política |
| Clave de cuenta | Rotar la clave (invalida las SAS firmadas con ella) |

> Una SAS **ad hoc** (sin política) **no se puede revocar de forma individual**: por eso el vencimiento corto es tu mejor defensa.

---

## 7. Presigned URL en AWS (S3)

### 7.1 Qué es

Una URL generada con las **credenciales de quien firma**. La URL otorga **la operación firmada** (por ejemplo, `GET` de un objeto o `PUT` de un objeto) durante un tiempo.

Parámetros típicos: `X-Amz-Algorithm`, `X-Amz-Credential`, `X-Amz-Date`, **`X-Amz-Expires`** (segundos), `X-Amz-SignedHeaders`, `X-Amz-Signature`.

**Reglas importantes**
- Los permisos son **los del firmante**: si pierde el permiso, la URL deja de funcionar.
- Vencimiento máximo: **7 días** con credenciales IAM de larga duración; con **credenciales temporales** (roles), no supera la vigencia de esa sesión.
- La URL es **para una operación** (GET o PUT) sobre **un objeto**.

### 7.2 CLI

```bash
# LECTURA (solo GET) por 15 minutos
aws s3 presign s3://modalima-fotos/2026/10/foto.jpg --expires-in 900
```
La CLI genera presigned de **lectura**. Para **escritura** se usa el SDK (siguiente sección).

### 7.3 Java (SDK v2)

```java
try (S3Presigner presigner = S3Presigner.create()) {

    // ---- LECTURA 15 minutos ----
    GetObjectRequest get = GetObjectRequest.builder()
        .bucket("modalima-fotos").key("2026/10/foto.jpg").build();

    String urlLectura = presigner.presignGetObject(
        GetObjectPresignRequest.builder()
            .signatureDuration(Duration.ofMinutes(15))
            .getObjectRequest(get).build())
        .url().toString();

    // ---- ESCRITURA 15 minutos ----
    PutObjectRequest put = PutObjectRequest.builder()
        .bucket("modalima-subidas").key("entrada/" + UUID.randomUUID() + ".pdf")
        .contentType("application/pdf").build();

    String urlEscritura = presigner.presignPutObject(
        PutObjectPresignRequest.builder()
            .signatureDuration(Duration.ofMinutes(15))
            .putObjectRequest(put).build())
        .url().toString();
}
```

```bash
# Subir con la URL (el Content-Type debe coincidir con el firmado)
curl -X PUT -H "Content-Type: application/pdf" --data-binary @pedido-123.pdf "$URL_ESCRITURA"
```

### 7.4 Subidas desde el navegador con restricciones

Para limitar **tamaño y tipo**, S3 ofrece **presigned POST** con una *policy* (condiciones como `content-length-range` y prefijo de la clave). Es más seguro que un PUT abierto.

### 7.5 Restricciones adicionales

Se aplican con **políticas del bucket/IAM** (condiciones como IP de origen, VPC endpoint o TLS), ya que la URL usa los permisos del firmante.

---

## 8. Pre-Authenticated Request (PAR) en OCI

### 8.1 Qué es

Un **PAR** es una URL creada **en el servidor**: OCI **guarda** el PAR (nombre, alcance, vencimiento). La **URL completa se muestra solo al crearlo**. Se puede **listar y borrar** (revocar).

### 8.2 Tipos de acceso

| `access-type` | Qué permite | Alcance |
|---|---|---|
| `ObjectRead` | **Leer** un objeto | Un objeto |
| `ObjectWrite` | **Escribir** un objeto | Un objeto |
| `ObjectReadWrite` | Leer y escribir | Un objeto |
| `AnyObjectRead` | Leer cualquier objeto | Todo el bucket (o un prefijo) |
| `AnyObjectWrite` | Escribir cualquier objeto | Todo el bucket (o un prefijo) |
| `AnyObjectReadWrite` | Leer y escribir | Todo el bucket (o un prefijo) |

Opcionalmente un PAR de bucket puede permitir **listar** objetos.

### 8.3 CLI

```bash
NS=$(oci os ns get --query 'data' --raw-output)

# LECTURA de un objeto, vence en 15 minutos
oci os preauth-request create --namespace-name $NS --bucket-name fotos \
  --name par-lectura-foto --access-type ObjectRead \
  --object-name 2026/10/foto.jpg \
  --time-expires 2026-10-16T16:15:00Z

# ESCRITURA de un objeto
oci os preauth-request create --namespace-name $NS --bucket-name subidas \
  --name par-subida-pedido --access-type ObjectWrite \
  --object-name entrada/pedido-123.pdf \
  --time-expires 2026-10-16T16:15:00Z
```

La respuesta incluye un `access-uri`. La URL final es:
```
https://objectstorage.<REGION>.oraclecloud.com<access-uri>
```

```bash
# Subir
curl -X PUT --data-binary @pedido-123.pdf "$URL_PAR_ESCRITURA"

# Revocar
oci os preauth-request delete --namespace-name $NS --bucket-name subidas --par-id <PAR_ID>
```

### 8.4 Java (SDK)

```java
CreatePreauthenticatedRequestDetails detalles =
    CreatePreauthenticatedRequestDetails.builder()
        .name("par-lectura-foto")
        .accessType(CreatePreauthenticatedRequestDetails.AccessType.ObjectRead)
        .objectName("2026/10/foto.jpg")
        .timeExpires(Date.from(Instant.now().plus(15, ChronoUnit.MINUTES)))
        .build();

CreatePreauthenticatedRequestResponse r = os.createPreauthenticatedRequest(
    CreatePreauthenticatedRequestRequest.builder()
        .namespaceName(namespace).bucketName("fotos")
        .createPreauthenticatedRequestDetails(detalles).build());

String url = "https://objectstorage." + region + ".oraclecloud.com"
           + r.getPreauthenticatedRequest().getAccessUri();
```
> Verifica nombres exactos en la versión de SDK que uses. Quien crea PAR necesita un permiso específico de administración de PAR además del acceso al bucket (verifica el verbo vigente en la política).

### 8.5 Diferencia clave

El PAR **existe como recurso**: puedes **verlo y borrarlo**. En SAS ad hoc, Presigned URL y Signed URL la firma no se guarda en el servidor; por eso no se revocan una a una.

---

## 9. Signed URL en GCP (Cloud Storage)

### 9.1 Qué es

Una URL **firmada con la clave de una cuenta de servicio**. Concede un **método HTTP** concreto (`GET`, `PUT`, `DELETE`…) sobre **un objeto** durante un tiempo (máximo **7 días** con firma V4).

### 9.2 Cómo se firma

| Forma | Nota |
|---|---|
| Con **llave JSON** de la cuenta de servicio | Funciona, pero evita crear llaves (riesgo) |
| **Sin llave** (IAM Credentials `signBlob`) | Recomendada: la cuenta de servicio necesita permiso para **firmar por sí misma** (`roles/iam.serviceAccountTokenCreator`) |

### 9.3 CLI

```bash
# LECTURA 15 minutos (suplantando a una cuenta de servicio, sin llaves)
gcloud storage sign-url gs://modalima-fotos/2026/10/foto.jpg \
  --duration=15m --http-verb=GET \
  --impersonate-service-account=firmador@mi-proyecto.iam.gserviceaccount.com

# ESCRITURA 15 minutos
gcloud storage sign-url gs://modalima-subidas/entrada/pedido-123.pdf \
  --duration=15m --http-verb=PUT \
  --impersonate-service-account=firmador@mi-proyecto.iam.gserviceaccount.com
```

```bash
curl -X PUT -H "Content-Type: application/pdf" --data-binary @pedido-123.pdf "$URL_FIRMADA"
```

### 9.4 Java

```java
Storage storage = StorageOptions.getDefaultInstance().getService();

// ---- LECTURA 15 minutos ----
BlobInfo foto = BlobInfo.newBuilder(BlobId.of("modalima-fotos", "2026/10/foto.jpg")).build();
URL urlLectura = storage.signUrl(foto, 15, TimeUnit.MINUTES,
    Storage.SignUrlOption.withV4Signature());

// ---- ESCRITURA 15 minutos ----
BlobInfo subida = BlobInfo.newBuilder(
        BlobId.of("modalima-subidas", "entrada/" + UUID.randomUUID() + ".pdf"))
    .setContentType("application/pdf").build();

URL urlEscritura = storage.signUrl(subida, 15, TimeUnit.MINUTES,
    Storage.SignUrlOption.httpMethod(HttpMethod.PUT),
    Storage.SignUrlOption.withExtHeaders(Map.of("Content-Type", "application/pdf")),
    Storage.SignUrlOption.withV4Signature());
```
> Si la aplicación usa credenciales de **usuario** (por ejemplo, tu sesión local), fallará porque no pueden firmar. En GCP corre con una **cuenta de servicio** o suplántala.

Para subidas desde el navegador con límite de tamaño y tipo existe el **signed policy document** (POST).

---

## 10. Comparativa de las 4 nubes

| | Azure SAS | AWS Presigned URL | OCI PAR | GCP Signed URL |
|---|---|---|---|---|
| **Qué firma** | Clave de delegación (Entra ID) o clave de cuenta | Credenciales del firmante | OCI lo crea y lo **guarda** | Clave de cuenta de servicio (o `signBlob`) |
| **Estado en servidor** | No (salvo política almacenada) | No | **Sí** (recurso PAR) | No |
| **Permisos** | Letras (`r`, `c`, `w`, `d`, `l`…) | La operación firmada (GET/PUT) y los permisos del firmante | `ObjectRead`, `ObjectWrite`, `ObjectReadWrite` y variantes `AnyObject…` | El método HTTP firmado y los permisos de la cuenta de servicio |
| **Lectura** | `r` | `presignGetObject` | `ObjectRead` | `GET` |
| **Escritura / subida** | `cw` (o `w`) | `presignPutObject` | `ObjectWrite` | `PUT` |
| **Vencimiento máximo** | La clave de delegación dura hasta 7 días | 7 días (credenciales largas); o la sesión | Lo defines al crear | 7 días (V4) |
| **Revocación** | Revocar claves de delegación / política / rotar clave | Quitar permisos al firmante, rotar credenciales | **Borrar el PAR** | Quitar permisos o desactivar la cuenta de servicio |
| **Restricción por IP** | Sí (`sip`) | Mediante políticas (condiciones) | Verifica la opción vigente | No en la URL: usa políticas de red / condiciones |
| **Alcance** | Blob, contenedor o directorio | Un objeto | Objeto, prefijo o bucket | Un objeto |
| **Subida desde navegador con límites** | SAS + CORS | Presigned **POST** | PAR + CORS | **Signed policy document** + CORS |

**Lo que comparten las cuatro:**
1. **Quien tenga la URL tiene el acceso** (es una credencial portadora, como una contraseña).
2. La URL **no valida el contenido**: tú debes revisar tipo, tamaño y malware después.
3. **No** deben quedar en logs, correos masivos ni repositorios.
4. Cuanto **más corta** la vida de la URL, mejor.

---

## 11. Qué permiso dar según la necesidad

| Necesidad | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| Descargar un archivo | `r` | Presigned GET | `ObjectRead` | `GET` |
| Subir un archivo nuevo | `cw` | Presigned PUT | `ObjectWrite` | `PUT` |
| Reemplazar un archivo | `w` | Presigned PUT | `ObjectWrite` / `ObjectReadWrite` | `PUT` |
| Ver qué hay en una carpeta | `l` (SAS de contenedor) | Lo hace el backend con credenciales | PAR de bucket con listado | Lo hace el backend |
| Borrar | `d` (**evitar**) | **Evitar** | **Evitar** | **Evitar** |
| Subida desde navegador con límite de tamaño | SAS + validación posterior | Presigned POST con policy | PAR + validación posterior | Signed policy document |

---

## 12. Errores graves con SAS y equivalentes

- SAS **sin vencimiento** o con vencimiento de meses.
- Dar **`rwdl`** (todo) a un cliente que solo debe subir.
- **SAS de cuenta** o clave de cuenta en una aplicación móvil o web.
- Generar la SAS en el **navegador** (la clave tendría que estar allí).
- **Registrar la URL completa** en logs, trazas o herramientas de monitoreo.
- Permitir que el usuario **elija el nombre** del blob (sobrescritura, ataques de ruta): genera un nombre con UUID en el servidor.
- Dar a un cliente una SAS de **contenedor** cuando bastaba una de **blob**.
- Olvidar que **rotar la clave de cuenta** invalida SAS legítimas (y planificarlo).
- No poner `https-only`.
- Confiar en que el archivo subido es seguro: **analízalo** antes de procesarlo.

---

## 13. Patrón Claim Check: enviar la URL por una cola

### 13.1 El problema

Las colas y los streams aceptan mensajes **pequeños** (los límites van de KB a pocos MB y cambian por servicio y tier; verifícalos). Un PDF de 40 MB o un video **no cabe**.

### 13.2 La idea

Como en un guardarropa: dejas el abrigo y recibes **un ticket**. Por la cola viaja **el ticket**, no el abrigo.

```
┌──────────┐ 1. pide permiso de subida ┌─────────┐
│ Cliente  │ ─────────────────────────►│ Backend │
│ (web/app)│ ◄──────────────────────── │  (API)  │
└────┬─────┘ 2. URL temporal de ESCRITURA└────┬────┘
     │ 3. sube el archivo directo               │
     ▼                                          │
┌──────────────────┐                            │
│ Storage (blob)   │                            │
└────────┬─────────┘                            │
         │ 4. evento "archivo creado" o         │
         │    notificación del cliente          │
         ▼                                      ▼
┌──────────────────────────────────────────────────┐
│ COLA / TÓPICO:  { blobUrl, tamaño, hash, tipo }  │  ← el "ticket"
└────────────────────────┬─────────────────────────┘
                         │ 5. el consumidor lee el mensaje
                         ▼
                 ┌──────────────┐  6. descarga el blob con su
                 │ Procesador   │ ──── identidad (o URL de LECTURA)
                 └──────────────┘
```

### 13.3 Dos variantes para producir el mensaje

| Variante | Cómo | Cuándo |
|---|---|---|
| **A. Dirigida por el backend** | El cliente sube y avisa a la API ("terminé"); la API valida y **publica el mensaje** | Quieres control y validaciones antes de encolar |
| **B. Dirigida por eventos** | El storage emite "blob creado" y un servicio lo encola | Quieres desacoplar totalmente; funciona con subidas de cualquier origen |

### 13.4 El mensaje (el "ticket")

```json
{
  "mensajeId": "7f2a2e2e-6a47-4c2b-9d8e-0a7f8a1c1e11",
  "tipo": "archivo.recibido",
  "blobUrl": "https://stmodalimaestudio01.blob.core.windows.net/subidas/entrada/pedido-123.pdf",
  "tamanoBytes": 4382211,
  "contentType": "application/pdf",
  "sha256": "9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08",
  "creadoEn": "2026-10-16T16:02:11Z"
}
```

**Detalles que importan**
- Lo recomendable es que el mensaje lleve **solo la URL sin SAS**, y que el consumidor use su **identidad administrada** con rol de lectura. Así no viajan credenciales por la cola.
- Si incluyes una **SAS de lectura**, trata el mensaje como **secreto**, usa un vencimiento **mayor** que el tiempo máximo de reintentos de la cola, o los reintentos fallarán con la SAS vencida.
- Incluye **hash y tamaño** para validar integridad.
- Procesa de forma **idempotente** (el mismo mensaje puede llegar dos veces).
- Define qué pasa si el blob **ya no existe** (mensaje a *dead-letter*).
- Borra o archiva el blob cuando acabe el proceso (ciclo de vida).

### 13.5 Ejemplo en Java (Azure)

**Productor** (variante A: la API publica después de validar)
```java
ServiceBusSenderClient emisor = new ServiceBusClientBuilder()
    .fullyQualifiedNamespace("sb-modalima.servicebus.windows.net")
    .credential(new DefaultAzureCredentialBuilder().build())
    .sender().queueName("archivos")
    .buildClient();

String json = """
    {"tipo":"archivo.recibido",
     "blobUrl":"%s",
     "tamanoBytes":%d,
     "contentType":"%s"}
    """.formatted(blobUrlSinSas, tamano, contentType);

emisor.sendMessage(new ServiceBusMessage(json));
```

**Consumidor** (descarga con su identidad)
```java
ServiceBusProcessorClient procesador = new ServiceBusClientBuilder()
    .fullyQualifiedNamespace("sb-modalima.servicebus.windows.net")
    .credential(new DefaultAzureCredentialBuilder().build())
    .processor().queueName("archivos")
    .processMessage(ctx -> {
        String cuerpo = ctx.getMessage().getBody().toString();
        String blobUrl = extraerBlobUrl(cuerpo);               // parseo JSON
        BlobClient blob = new BlobClientBuilder()
            .endpoint(blobUrl)
            .credential(new DefaultAzureCredentialBuilder().build())
            .buildClient();
        try (ByteArrayOutputStream out = new ByteArrayOutputStream()) {
            blob.downloadStream(out);
            procesar(out.toByteArray());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
    })
    .processError(ctx -> System.err.println("Error: " + ctx.getException()))
    .buildProcessorClient();

procesador.start();
```
> Para archivos muy grandes, descarga **por streams a disco** en lugar de cargar todo en memoria.

### 13.6 Equivalentes del patrón

| Parte | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| Archivo | Blob | S3 | Object Storage | Cloud Storage |
| Cola / tópico | Service Bus / Storage Queue | SQS / SNS | OCI Queue | Pub/Sub |
| Evento al crear | Event Grid `BlobCreated` | S3 Event Notifications | Events (`createobject`) | Notificaciones a Pub/Sub / Eventarc |
| Procesador | Function / AKS | Lambda / ECS / EKS | Functions / OKE | Cloud Run / GKE |
| Variante AWS conocida | | **SQS Extended Client**: guarda el cuerpo grande en S3 y manda la referencia | | |

---

## 14. Eventos al subir un archivo

| Nube | Mecanismo | Ejemplo |
|---|---|---|
| **Azure** | **Event Grid** sobre la cuenta de storage; evento `Microsoft.Storage.BlobCreated` | Destino: Function, cola o Service Bus; filtro por prefijo |
| **AWS** | **S3 Event Notifications** (`s3:ObjectCreated:*`) o EventBridge | Destino: SQS, SNS o Lambda |
| **OCI** | **Events** con el tipo `com.oraclecloud.objectstorage.createobject` (habilita "emitir eventos de objeto" en el bucket) | Destino: Functions, Notifications o Streaming |
| **GCP** | **Notificaciones de Cloud Storage a Pub/Sub** (`OBJECT_FINALIZE`) o **Eventarc** | Destino: Pub/Sub, Cloud Run |

```bash
# Azure: evento de "blob creado" de la carpeta entrada/ hacia una cola de Service Bus
STID=$(az storage account show -g $RG -n $ST --query id -o tsv)

az eventgrid system-topic create -g $RG -n evt-st-subidas \
  --source $STID --topic-type microsoft.storage.storageaccounts -l eastus2

az eventgrid system-topic event-subscription create -g $RG \
  --system-topic-name evt-st-subidas -n sub-entrada \
  --endpoint-type servicebusqueue --endpoint <ID_DE_LA_COLA> \
  --included-event-types Microsoft.Storage.BlobCreated \
  --subject-begins-with /blobServices/default/containers/subidas/blobs/entrada/
```
> Para entregar a Service Bus con identidad hay que configurar la identidad de entrega y permisos. Revisa los parámetros con `--help`.

```bash
# GCP: notificación de objetos nuevos a un tópico de Pub/Sub
gcloud storage buckets notifications create gs://modalima-subidas \
  --topic=archivos-recibidos --event-types=OBJECT_FINALIZE
```

Todos los sistemas de eventos entregan **al menos una vez**: tu consumidor debe ser **idempotente**.

---

## 15. Acceso privado y SAS

- Un Private Endpoint (`privatelink.blob.core.windows.net`) hace que el blob tenga IP privada (módulos 01 y 02).
- Una SAS en una cuenta **solo privada** funciona **únicamente** para clientes que alcancen ese endpoint. Un usuario en su casa recibiría un *timeout*.
- Si los clientes son externos y deben subir archivos directamente, decide: **cuenta pública restringida** solo para subidas (con SAS de escritura cortas y análisis posterior) o un **endpoint de subida intermedio**.
- Equivalentes: S3 con endpoint de VPC y políticas por `aws:SourceVpce`; OCI con Service Gateway; GCP con Private Google Access / PSC y VPC Service Controls.

---

## 16. IAM del módulo

| Quién | Qué hace | Azure | AWS | OCI | GCP |
|---|---|---|---|---|---|
| App que lee datos | Leer objetos | Storage Blob Data Reader | `s3:GetObject` | `read objects` | `roles/storage.objectViewer` |
| App que sube | Crear objetos | Storage Blob Data Contributor | `s3:PutObject` | `manage objects` (o `use`) acotado | `roles/storage.objectCreator` |
| App que genera URLs temporales | Firmar | **Storage Blob Delegator** + rol de datos | Permisos del firmante sobre esas acciones | Permiso de crear PAR + acceso al bucket | `serviceAccountTokenCreator` (firmar) + `objectViewer`/`objectCreator` |
| Administrador | Gestionar la cuenta/bucket | Storage Account Contributor | `s3:*` acotado | `manage buckets` | `roles/storage.admin` |

---

## 17. Casos de uso de vida real

### Caso 1 · Subida directa de fotos de producto
- **Problema:** las fotos pasaban por la API y la saturaban.
- **Solución:** la API genera una **SAS de escritura de 10 minutos** a un nombre con UUID; el navegador sube directo al storage; luego avisa a la API.
- **Resultado:** la API dejó de ser el cuello de botella.
- **Lección:** el archivo viaja por el storage, no por tu backend.

### Caso 2 · Boleta en PDF con enlace temporal
- **Problema:** enviar boletas por correo como adjuntos exponía datos.
- **Solución:** correo con enlace **SAS de lectura de 24 horas** (o una página que la genera al hacer clic, con validación de sesión, y vigencia de 5 minutos).
- **Lección:** mejor generar la URL **al momento del clic** que enviarla por correo.

### Caso 3 · Archivos de 2 GB con Claim Check
- **Problema:** un proveedor enviaba catálogos enormes y el procesamiento fallaba por tamaño de mensaje.
- **Solución:** subida por SAS, evento `BlobCreated`, mensaje con la URL y el hash a la cola, y un procesador que descarga por *streaming*.
- **Resultado:** procesamiento estable y reintentos seguros.
- **Lección:** por la cola va **la referencia**, no el dato.

### Caso 4 · Proveedor externo que sube un CSV diario
- **Problema:** el proveedor usaba la clave de la cuenta compartida por correo.
- **Solución:** SAS de **escritura** limitada a un prefijo y a la IP del proveedor, con vencimiento semanal renovado automáticamente; análisis del archivo antes de moverlo a la zona de procesamiento.
- **Lección:** acceso externo = mínimo, con vencimiento y con revisión del contenido.

### Caso 5 · Logs que cuestan una fortuna
- **Problema:** 3 TB de logs en el tier caliente.
- **Solución:** regla de ciclo de vida: frío a los 30 días, archivo a los 180, borrado a los 2 años.
- **Resultado:** el costo bajó de forma notable sin perder trazabilidad.
- **Lección:** el ciclo de vida es el mejor ahorro del storage.

---

## 18. Qué hacer / qué NO hacer

**Qué hacer**
- Preferir **identidad administrada + RBAC** para aplicaciones.
- Usar **SAS de delegación de usuario** para accesos temporales de terceros.
- Vencimientos **cortos** (minutos) y permisos **mínimos**.
- Generar la URL en el **backend**, después de **autorizar** al usuario.
- Nombres de objeto generados por el servidor (UUID).
- Exigir **HTTPS** y TLS 1.2 o superior.
- Analizar los archivos subidos (malware, tipo, tamaño).
- Activar versionado, soft delete y ciclo de vida.
- Para colas: enviar **referencias**, no archivos.

**Qué NO hacer**
- Compartir la clave de cuenta.
- Dar SAS sin vencimiento o con `d` (borrado).
- Registrar URLs firmadas en logs.
- Dejar contenedores públicos "por comodidad".
- Dejar que el cliente decida la ruta destino.
- Mandar archivos grandes dentro de mensajes.
- Asumir que una subida correcta significa un archivo seguro.

---

## 19. Troubleshooting

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| Azure 403 `AuthenticationFailed` ("signature not the same") | URL modificada, codificación doble, clave rotada | Comparar la URL con la original | Regenerar la SAS; no editar parámetros |
| Azure 403 `AuthorizationPermissionMismatch` / "not authorized using this permission" | La SAS no incluye el permiso necesario | Revisar `sp` | Generar con el permiso correcto |
| Azure 403 recién creada la SAS | Desfase de reloj (`st` en el futuro) | Hora UTC y `st` | Poner inicio unos minutos antes o no usarlo |
| Azure 403 al usar una SAS vencida | `se` en el pasado | Parámetro `se` | Generar otra |
| Azure 403 desde otra red | Restricción `sip` o firewall del storage | `sip` y reglas de red | Ajustar rango o red |
| Azure 400 al subir con PUT | Falta el encabezado `x-ms-blob-type` | Encabezados de la petición | Agregarlo (`BlockBlob`) |
| Azure `generateUserDelegationKey` falla | Falta el rol Delegator | Roles de la identidad | Asignar *Storage Blob Delegator* |
| Azure: no puedo crear SAS de cuenta/servicio | Clave compartida deshabilitada | Configuración de la cuenta | Usar SAS de delegación de usuario |
| Navegador: error de **CORS** al subir | CORS no configurado | Consola del navegador | Configurar CORS del servicio con origen y métodos |
| AWS `SignatureDoesNotMatch` | `Content-Type` o encabezados distintos a los firmados; región errónea | Comparar encabezados | Firmar y enviar exactamente lo mismo |
| AWS `AccessDenied` con presigned válida | El firmante no tiene permiso | Política del firmante | Dar permiso al firmante |
| AWS "Request has expired" | Vencimiento o credencial temporal expirada | `X-Amz-Expires` y sesión | Generar de nuevo |
| OCI 404 al usar un PAR | PAR vencido o borrado | Listar PAR del bucket | Crear otro |
| GCP `SignatureDoesNotMatch` | Encabezados no coinciden o reloj | Cabeceras firmadas | Enviar las mismas cabeceras |
| GCP "no se puede firmar" | Credenciales de usuario sin capacidad de firma | Credencial activa | Usar cuenta de servicio o suplantación |
| Timeout con SAS | El storage solo es privado y el cliente está fuera | `nslookup` / `ConnCheck` | Acceso por red privada o endpoint de subida |

---

## 20. Repaso y entrevista

**Repaso**
1. ¿Qué diferencia hay entre una SAS de delegación de usuario y una firmada con la clave de cuenta?
2. ¿Qué permisos pones para que un cliente suba un archivo nuevo? ¿Y para que lo descargue?
3. ¿Por qué un PAR de OCI es "más revocable" que una Presigned URL de AWS?
4. ¿Qué es el patrón Claim Check y qué problema resuelve?
5. ¿Por qué debes cuidar que la SAS no venza antes de que se reintente un mensaje?

**Entrevista**
- Diseña la subida de archivos de 500 MB desde un navegador, con análisis antivirus y procesamiento asíncrono.
- ¿Cómo revocarías de inmediato un acceso temporal entregado hace 10 minutos?
- ¿Cómo darías acceso de escritura a un proveedor externo con el menor riesgo posible?
