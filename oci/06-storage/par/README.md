# Oracle OCI · Storage · PAR (Pre-Authenticated Requests)

Una PAR es una URL con un secreto incrustado que da acceso a un objeto (o a un bucket) **sin credenciales de OCI**, por un tiempo limitado y con permisos acotados: leer, escribir o ambos. Es la forma de compartir o recibir archivos sin abrir el bucket.

## 1. Qué es

**Analogía:** el código temporal de un casillero de aeropuerto. Quien tenga el código abre **ese** casillero hasta la hora indicada; no abre los demás, y después el código no sirve.

```
 App (con IAM) ──CreatePreauthenticatedRequest──► Object Storage
        │  ◄── accessUri: /p/<secreto>/n/<ns>/b/comprobantes/o/pedidos/…/P-100.pdf (vence en 15 min)
        ▼
 Cliente / socio (sin cuenta de OCI) ── GET o PUT con esa URL ──► el objeto
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Tipo de acceso** | `ObjectRead`, `ObjectWrite`, `ObjectReadWrite` (un objeto) o `AnyObjectRead/Write/ReadWrite` (todo el bucket o prefijo) |
| **Objeto o prefijo** | A qué aplica; con `Any*` puede limitarse a un prefijo |
| **Expiración** | `timeExpires` obligatorio |
| **Listado** | `bucketListingAction`: permitir o no listar objetos (solo en PAR de bucket) |
| **URI de acceso** | Se muestra **una sola vez** al crearla; OCI no la guarda en claro |
| **Identificador** | Sirve para listar y revocar (borrar) la PAR |

### Ciclo de vida
1. Tu servicio (con permisos IAM) crea la PAR con el mínimo alcance y vencimiento corto.
2. Entrega la URL completa (`https://objectstorage.<región>.oraclecloud.com` + `accessUri`).
3. El cliente usa la URL con `GET`/`PUT` simple.
4. Vence sola; o la revocas antes con `DeletePreauthenticatedRequest`.

### Lo que hay que saber
- **Quien tenga la URL tiene el acceso**: trátala como un secreto.
- Crear la PAR requiere `PAR_MANAGE` **y** los permisos del acceso que delega (no puedes dar más de lo que tienes).
- Si el usuario creador pierde permisos, la PAR deja de funcionar.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Descargar un comprobante desde el navegador del cliente | PAR `ObjectRead` de 5–15 min |
| Que el navegador suba la foto directo al bucket | PAR `ObjectWrite` de un nombre fijo |
| Un socio entrega archivos diarios | PAR `AnyObjectWrite` acotada a un prefijo, sin listado, renovada periódicamente |
| Acceso permanente para un sistema | **No**: identidad propia con IAM |
| Contenido público de verdad (logo) | CDN o bucket dedicado, no PAR eterna |
| Acceso a todo el bucket con listado | Casi nunca |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Portador (bearer)** | Quien tiene la URL tiene el permiso |
| **Mínimo alcance** | Un objeto, una operación, poco tiempo |
| **Revocación** | Borrar la PAR invalida la URL |
| **Subida directa** | El archivo no pasa por tu backend |

## 5. Cómo se usa
1. Crea PAR desde tu backend con reglas estrictas: [uso en Java](uso-en-java.md).
2. Para socios, una PAR de prefijo con Terraform (y rotación): [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
3. Listar y revocar: [`ejemplos/cli/par.sh`](ejemplos/cli/par.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Servicio que emite PAR | `manage objects` con `PAR_MANAGE` en el bucket | Lo que delega (`OBJECT_READ`/`OBJECT_CREATE`) |
| Portador de la URL | — | Exactamente lo que dice la PAR |
| Auditoría | `inspect` / Audit | Registro de accesos |

- Vencimiento corto, un objeto, sin listado.
- No registres la URL completa (registra solo el id de la PAR).
- Envíala por HTTPS y nunca en un correo masivo o un canal público.
- Vigila con Audit la creación de PAR `Any*` o con vencimientos largos.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| 5–15 minutos para descargas | PAR de un año |
| Nombre de objeto fijado por el backend | Dejar que el cliente elija dónde escribir |
| Revocar al terminar | Acumular cientos de PAR vivas |
| Validar el archivo subido (tamaño, tipo, antivirus) antes de usarlo | Procesar lo subido sin revisar |
| Registrar el id de la PAR | Registrar la URL |

## 8. Límites, costos y versiones
- **Costo:** sin cargo por la PAR; pagas almacenamiento, peticiones y salida *(verifica)*.
- **Límites** (verifica): PAR por bucket, vencimiento máximo.
- **Terraform:** `oci_objectstorage_preauthrequest`.
- **SDK:** `ObjectStorageClient.createPreauthenticatedRequest`, `deletePreauthenticatedRequest`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
