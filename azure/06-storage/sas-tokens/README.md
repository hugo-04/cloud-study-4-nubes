# Azure · Storage · SAS tokens (Shared Access Signature)

## 1. Qué es

**Una SAS es una URL firmada que da acceso limitado, temporal y delegado a un recurso de Storage, sin compartir tu identidad ni tus claves.** Quien tiene la URL tiene el acceso (es una credencial "al portador"), por eso se hace corta, mínima y se genera en el servidor.

Analogía: **la llave de un solo casillero que caduca en 15 minutos**. Tú (el backend) tienes el llavero maestro; le entregas al cliente una llave que abre *ese* casillero, para *esa* acción y solo *ese* rato.

```
https://stmodalima01.blob.core.windows.net/fotos/2026/10/foto.jpg
  ?sv=2022-11-02            ← versión del servicio
  &st=2026-10-16T16:00:00Z  ← inicio de validez (opcional)
  &se=2026-10-16T16:15:00Z  ← FIN de validez
  &sr=b                     ← recurso: b=blob
  &sp=r                     ← permisos: r=read
  &spr=https                ← solo HTTPS
  &sip=203.0.113.0-203.0.113.255  ← IPs permitidas (opcional)
  &skoid=…&sktid=…&skt=…&ske=…&sks=b&skv=2022-11-02   ← datos de la clave de delegación (SAS de delegación)
  &sig=FIRMA                ← la firma: no se puede modificar nada
```

---

## 2. Cómo funciona por dentro

### 2.1 Quién firma y qué comprueba Storage
1. El **firmante** (tu backend) obtiene una **clave de delegación de usuario** de Entra ID (válida hasta 7 días) —o usa la clave de la cuenta— y calcula la firma HMAC-SHA256 sobre los parámetros (recurso, permisos, tiempos, IP…).
2. El **cliente** presenta la URL. Storage recalcula la firma; si coincide y los parámetros permiten la operación (permiso, tiempo, IP, protocolo), **autoriza**.
3. En la **SAS de delegación**, además, Storage comprueba que el **firmante todavía tiene permiso** (RBAC/ABAC) sobre el recurso: *acceso efectivo = permisos de la SAS ∩ permisos del firmante en el momento de uso*. Si le quitas el rol al firmante, las SAS emitidas dejan de funcionar.

### 2.2 Los tres tipos

| Tipo | Se firma con | Alcance | Revocación | Recomendación |
|---|---|---|---|---|
| **User delegation SAS** | Clave de delegación obtenida con **Entra ID** | Blob, contenedor, directorio (HNS) | Revocar claves de delegación o quitar permisos al firmante | **La recomendada** |
| **Service SAS** | Clave de la cuenta | Un recurso de un servicio (blob, cola, tabla, share) | Política de acceso almacenada, o rotar la clave | Solo si no hay alternativa |
| **Account SAS** | Clave de la cuenta | Varios servicios y operaciones a nivel de cuenta | Rotar la clave | **Evitar** |

> Si la cuenta tiene `allowSharedKeyAccess=false`, **solo** puedes emitir SAS de delegación de usuario.

### 2.3 Parámetros (referencia)

| Parámetro | Significado |
|---|---|
| `sv` | Versión de la API con la que se interpreta la SAS |
| `st` / `se` | Inicio / **expiración** (UTC, ISO 8601) |
| `sr` | Recurso: `b` blob, `bv` versión, `bs` snapshot, `c` contenedor, `d` directorio |
| `sp` | **Permisos** (ver 2.4) |
| `sip` | IP o rango permitido |
| `spr` | Protocolo: `https` o `https,http` |
| `si` | Id de la política de acceso almacenada |
| `rscc`, `rscd`, `rsce`, `rscl`, `rsct` | Sobrescriben cabeceras de **respuesta** (`Cache-Control`, `Content-Disposition`, etc.): p. ej. `rscd=attachment; filename="boleta.pdf"` fuerza el nombre de descarga |
| `sdd` | Profundidad de directorio (HNS) |
| `ses` | Ámbito de cifrado |
| `skoid`, `sktid`, `skt`, `ske`, `sks`, `skv` | Identifican la **clave de delegación** |
| `saoid`, `suoid`, `scid` | Id del agente/usuario autorizado y correlación (SAS de delegación) |
| `ss`, `srt` | Servicios y tipos de recurso (solo Account SAS) |
| `sig` | Firma |

### 2.4 Permisos (`sp`)

| Letra | Permiso | Aplica a | Para qué |
|---|---|---|---|
| **`r`** | **Read** | blob, contenedor | **Descargar** contenido y propiedades |
| **`a`** | Add | blob, contenedor | Añadir bloques a un *append blob* |
| **`c`** | Create | blob, contenedor | **Crear** un blob nuevo (o copiar) |
| **`w`** | **Write** | blob, contenedor | **Escribir / reemplazar** contenido y propiedades |
| **`d`** | Delete | blob, contenedor | Borrar |
| `x` | Delete version | blob | Borrar versiones |
| `y` | Permanent delete | blob | Borrado permanente (soft delete) |
| `l` | List | contenedor, directorio | Listar blobs |
| `t` | Tags | blob | Leer/escribir etiquetas |
| `f` | Filter by tags | contenedor | Buscar por etiquetas |
| `m` | Move | blob, directorio (HNS) | Mover/renombrar |
| `e` | Execute | blob, directorio (HNS) | Leer propiedades/ACL (HNS) |
| `o` | Ownership | HNS | Cambiar propietario |
| `p` | Permissions | HNS | Cambiar permisos/ACL |
| `i` | Set immutability | blob | Poner políticas de inmutabilidad |

Combinaciones habituales:

| Necesidad | `sp` | `sr` |
|---|---|---|
| Descargar un archivo | `r` | `b` |
| Subir un archivo **nuevo** | `cw` | `b` |
| Reemplazar uno existente | `w` | `b` |
| Subir con bloques grandes (varios `PUT`) | `cw` | `b` |
| Listar una carpeta | `l` | `c`/`d` |
| Subir **muchos** archivos a un prefijo | `cw` (+ `l`) | `c` o `d` |
| Borrar | `d` (**evítalo en clientes**) | — |

### 2.5 La clave de delegación de usuario
- Se pide con `Get User Delegation Key` (necesita el rol **Storage Blob Delegator** a nivel de cuenta o superior).
- Tiene su propio `start` y `expiry` (**máximo 7 días**). Ninguna SAS puede vivir más que su clave.
- **Reutilízala** entre muchas SAS (cachéala con margen): pedirla en cada petición es lento y puede estrangular.
- `az storage account revoke-delegation-keys` **invalida todas las SAS de delegación vigentes**.

### 2.6 Política de acceso almacenada (stored access policy)
Una política guardada **en el contenedor** (hasta 5): define permisos, inicio y expiración. Una SAS de servicio puede referenciarla por `si=`. **Revocas todas las SAS ligadas a esa política borrándola o editándola.** Útil para: entregar enlaces a terceros con revocación centralizada. (No aplica a SAS de delegación de usuario.)

### 2.7 Ad hoc vs. con política

| | Ad hoc (todo en la URL) | Con política almacenada |
|---|---|---|
| Revocación individual | **No** (solo rotar clave/revocar claves) | Sí, borrando la política |
| Parámetros | Todos en la URL | Permisos/tiempos en la política |
| Qué hacer | Vencimiento corto | Vencimiento corto + política |

### 2.8 Red
- Una SAS en una cuenta **solo privada** funciona únicamente para clientes que alcanzan el Private Endpoint. Un usuario en su casa recibe *timeout*.
- Si clientes externos suben directo, decide: cuenta pública restringida **solo** a subidas con SAS cortas + análisis posterior, o un endpoint intermedio.
- `sip` restringe por IP (cuidado con NAT y móviles).

### 2.9 Lo que una SAS **no** hace
- **No limita el tamaño** de lo que sube el cliente (a diferencia de un POST policy en otras plataformas). Hay que **validar después** (evento + comprobación) y borrar lo excesivo; o limitar por cuotas.
- **No valida el contenido** (tipo real, malware).
- **No es un token de usuario**: no sabe quién es el cliente; la identidad la pones tú al decidir emitirla.
- **No se revoca individualmente** si es ad hoc.

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- **Subida directa** desde navegador/móvil sin pasar el archivo por tu API (ahorra ancho de banda y CPU).
- **Descarga directa** de archivos privados con enlace temporal (boletas, reportes).
- **Entrega a terceros** (socios, proveedores) con acceso mínimo y vencimiento.
- **Claim Check:** la referencia del archivo viaja por una cola ([Claim Check](../claim-check/README.md)).
- Compartir con herramientas que no soportan Entra ID.

| NO la uses si | Alternativa |
|---|---|
| Tu servicio (con identidad administrada) accede a Storage | **Entra ID + RBAC** directo |
| Necesitas autenticar a un usuario final con su identidad | Entra ID/B2C y que tu API autorice |
| Necesitas imponer tamaño máximo o validar el cuerpo antes de aceptarlo | Subir por tu API o validar tras la subida |
| El acceso debe durar meses sin renovar | Rol RBAC + proceso de renovación, no una SAS larga |
| Compartes una cuenta entera "por comodidad" | Mínimo privilegio: un recurso, una acción |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **SAS** | URL firmada de acceso limitado | `?sv=…&sp=r&se=…&sig=…` |
| **Clave de delegación** | Clave temporal de Entra ID para firmar | Hasta 7 días |
| **Política almacenada** | Reglas guardadas en el contenedor y referenciadas por la SAS | `si=socios` |
| **Portador** | Quien tiene el token tiene el acceso | Trátala como contraseña |
| **Ad hoc** | SAS sin política | No se revoca sola |
| **Desfase de reloj** | Diferencia entre relojes que invalida `st` | Usa inicio −5 min o sin `st` |
| **Permiso efectivo** | SAS ∩ permisos del firmante | Pierdes el rol → la SAS muere |

---

## 5. Cómo se usa

**Flujo de subida directa (el más común)**
```
Navegador ──(1) POST /archivos/solicitud-subida {tipo, tamañoDeclarado}──► API (autentica y autoriza)
API  ──(2) genera nombre UUID + SAS de ESCRITURA de 10 min──► Navegador
Navegador ──(3) PUT bloques con la SAS──────────────────────► Blob Storage
Navegador ──(4) POST /archivos/{id}/confirmar────────────────► API
API  ──(5) comprueba tamaño/tipo/hash; (opcional) evento BlobCreated; encola el "ticket"──► Cola
```

Archivos: [CLI](ejemplos/cli/sas.sh) · [Terraform](ejemplos/terraform/main.tf) · [navegador (JS)](ejemplos/web/subida.js).

```bash
# SAS de LECTURA de 15 minutos (delegación de usuario)
az storage blob generate-sas --account-name $ST -c fotos -n 2026/10/foto.jpg \
  --permissions r --https-only --as-user --auth-mode login --full-uri \
  --expiry $(date -u -d "+15 minutes" '+%Y-%m-%dT%H:%MZ')

# Subir con la SAS (el encabezado x-ms-blob-type es obligatorio)
curl -X PUT -H "x-ms-blob-type: BlockBlob" -H "Content-Type: application/pdf" \
     --data-binary @pedido-123.pdf "$URL_SAS_ESCRITURA"
```

---

## 6. Seguridad
- **Vencimiento en minutos** (5–15 para subidas/descargas interactivas).
- **Permisos mínimos** y **un solo blob** (`sr=b`) siempre que se pueda.
- **Nombre del blob generado por el servidor** (UUID) y prefijo por usuario/tenant.
- **`https` obligatorio** (`spr=https`); IP (`sip`) si el cliente es conocido.
- **Nunca en logs, correos masivos ni repositorios**; enmascara `sig` en trazas.
- **Autoriza antes de firmar**: tu API decide si ese usuario puede subir/descargar eso.
- **SAS de delegación** por defecto; clave compartida deshabilitada.
- **Valida después**: tamaño, tipo real (magic bytes), antivirus (Defender for Storage), y solo entonces procesa.
- **CORS** acotado a tus orígenes.
- **Planifica la revocación**: política almacenada (servicio) o `revoke-delegation-keys`.

### IAM de este servicio

| Quién | Qué hace | Rol mínimo |
|---|---|---|
| Backend que emite SAS | Pedir la clave de delegación | *Storage Blob Delegator* (cuenta o superior) |
| Backend que emite SAS | Ser capaz de dar el permiso | Un rol de **datos** con ese permiso (p. ej. *Storage Blob Data Contributor*): la SAS no puede dar más de lo que tiene el firmante |
| Cliente (navegador) | Usar la URL | Ninguno: la SAS es la credencial |
| Procesador | Leer el blob subido | *Storage Blob Data Reader* (por identidad, sin SAS) |
| Seguridad | Revisar uso | *Reader* + logs `StorageBlobLogs` |

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- Generar la SAS en el **backend** tras autorizar al usuario.
- Cachear la **clave de delegación** y renovarla antes de que expire.
- Vencimientos cortos y permisos mínimos; `https` obligatorio.
- Confirmar la subida y **validar** (tamaño, tipo, hash, antivirus) antes de procesar.
- Responder con la SAS y los **encabezados requeridos** (`x-ms-blob-type`, `Content-Type`).
- Usar `rscd` para controlar el nombre de descarga.
- Para terceros: SAS de servicio con **política almacenada** (revocable) o delegación con ventana corta.
- Medir: logs de operaciones por `AuthenticationType = SAS`.

**Qué NO hacer**
- SAS sin vencimiento o de meses.
- Dar `rwdl` a un cliente que solo debe subir.
- SAS de cuenta o clave de cuenta en apps móviles/web.
- Generar la SAS en el navegador.
- Registrar la URL completa en logs o herramientas de monitoreo.
- Dejar que el usuario elija el nombre o la ruta del blob.
- Dar SAS de **contenedor** cuando bastaba una de **blob**.
- Olvidar que rotar la clave de cuenta invalida SAS legítimas.
- Confiar en que un archivo subido es seguro.

---

## 8. Límites, costos y versiones
- La SAS no cuesta; sí las **operaciones** y la **salida** de datos que provoca.
- Clave de delegación: máx. 7 días. Políticas almacenadas: máx. 5 por contenedor.
- Cada versión de servicio (`sv`) habilita capacidades distintas (p. ej. `sdd`, `ses`): *usa la que fije tu SDK y verifica compatibilidad con el proxy/CDN*.
- Con CDN/Front Door delante, las SAS en la URL participan en la clave de caché: *revisa cómo configuras la caché por query string*.

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
