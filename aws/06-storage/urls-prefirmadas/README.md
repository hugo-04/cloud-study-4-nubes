# AWS · Storage · URLs prefirmadas de S3

**Una URL prefirmada es un enlace a *un* objeto de S3 que lleva la firma de quien la creó, con fecha de caducidad.** Quien la tiene puede hacer **esa** operación (subir, bajar…) sin tener credenciales de AWS. Es la forma estándar de que el navegador o la app móvil suban y bajen archivos **directo a S3** sin pasar los bytes por tu API.

## 1. Qué es

**Analogía:** un **boleto de cine con fecha y hora**: sirve para una sala (objeto), una función (operación) y hasta cierta hora. El taquillero (tu backend) lo firma; la puerta (S3) solo comprueba la firma.

```
 Cliente (web/móvil)                Backend (tu API)                     S3
      │ 1. "quiero subir foto.png"      │                                 │
      ├────────────────────────────────►│ 2. valida (tipo, tamaño, tenant)│
      │                                 │    firma EN LOCAL (sin llamar a S3)
      │ 3. URL firmada + cabeceras      │                                 │
      │◄────────────────────────────────┤                                 │
      │ 4. PUT de los bytes ──────────────────────────────────────────────►│ valida firma y vigencia
      │ 5. 200 OK ◄──────────────────────────────────────────────────────── │
```

## 2. Cómo funciona por dentro

| Pieza | Qué hace |
|---|---|
| **Firma SigV4 en la query** | `X-Amz-Algorithm`, `X-Amz-Credential`, `X-Amz-Date`, `X-Amz-Expires`, `X-Amz-SignedHeaders`, `X-Amz-Signature` (y `X-Amz-Security-Token` con credenciales temporales) |
| **Se calcula en local** | Firmar es matemática con tu clave: no hace falta llamar a S3 |
| **Permisos** | S3 evalúa los permisos del **firmante en el momento de usar la URL**: si el rol pierde acceso, la URL deja de funcionar |
| **Caducidad** | Usuario IAM: hasta 7 días. **Con rol (credenciales temporales): caduca cuando caduca la sesión**, aunque pidas más |
| **Cabeceras firmadas** | Si firmas `Content-Type` (o checksum, cifrado…), el cliente **debe** enviar exactamente esos valores |
| **GET / PUT / HEAD / DELETE** | Una operación por URL; para multiparte se firma cada `UploadPart` |
| **POST prefirmado** | Formulario con una *política* firmada: permite **limitar tamaño** (`content-length-range`), prefijo y tipo |
| **Sobrescribir cabeceras de respuesta** | `response-content-disposition`, `response-content-type` para forzar el nombre de descarga |

> **Limitar el tamaño:** un PUT prefirmado **no** puede limitar el tamaño (solo si firmas el `Content-Length` exacto). Para «hasta 10 MB» usa **POST prefirmado** o valida después de subir (patrón [Claim Check](../claim-check/README.md)).

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Subida directa de fotos, PDF, video desde el navegador/app | **URL prefirmada (PUT o POST)** |
| Descarga temporal de un archivo privado | **URL prefirmada (GET)** |
| Muchas descargas, usuarios globales, caché | **CloudFront con URLs firmadas** ([guía](../../05-ingress-api/cloudfront-waf/README.md)) |
| Tu API debe inspeccionar/transformar los bytes | Pasar por la API (o validar tras subir con eventos) |
| Compartir con una identidad conocida de tu organización | Roles de IAM / Access Points, no URLs |
| Enlace que no debe poder reutilizarse | URLs son reutilizables hasta caducar: añade clave única + validar al subir |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Presigned URL** | Enlace temporal que lleva la firma del backend |
| **Firmante** | La identidad (rol) cuyos permisos usa la URL |
| **Cabecera firmada** | Valor que el cliente debe enviar tal cual |
| **POST con política** | Formulario con reglas firmadas (tamaño, tipo, prefijo) |
| **CORS** | Permiso del bucket para que el navegador (otro origen) suba directo |
| **Caducidad efectiva** | El menor entre lo pedido y la vida de las credenciales |

## 5. Cómo se usa
1. El backend valida la solicitud (tenant, tipo, tamaño) y **elige la clave** (no el cliente).
2. Firma con `S3Presigner` (PUT o POST) con 5–15 minutos de vida.
3. Devuelve URL + cabeceras (y la clave).
4. El cliente sube con **exactamente** esas cabeceras.
5. Un evento de S3 ([eventos de S3](../eventos-s3/README.md)) o una confirmación valida el resultado.
6. CORS del bucket: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf) y [`ejemplos/json/cors.json`](ejemplos/json/cors.json). Prueba con [`ejemplos/cli/presign.sh`](ejemplos/cli/presign.sh).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **Rol del backend (firmante)** | — | `s3:PutObject` / `s3:GetObject` solo sobre el prefijo que firma; `kms:GenerateDataKey`/`Decrypt` si hay SSE-KMS |
| **Cliente con la URL** | — | Solo la operación firmada, hasta que caduque |
| **Pipeline** | CORS y política del bucket | — |

- **La URL es un secreto mientras vive:** no la registres en logs ni en analítica; tampoco en `Referer` (descarga con `Referrer-Policy: no-referrer`).
- **Vida corta** (minutos) y clave única por intento; la clave la fija el backend.
- **Cuidado con políticas de bucket restrictivas** (`aws:SourceVpce`, `aws:SourceIp`): bloquean al navegador del cliente.
- **Valida lo que llegó**: tamaño real, tipo real (no confíes en `Content-Type`), antivirus, checksum.
- Un rol con permisos amplios firmando URLs **amplía** lo que un atacante puede lograr con un solo enlace filtrado: acota el prefijo.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| 5–15 min de vida; clave única generada por el backend | URLs de días «por comodidad» |
| Firmar `Content-Type` y checksum | Dejar que el cliente decida clave y tipo |
| POST con `content-length-range` si importa el tamaño | Fiarse de un campo `tamano` que manda el cliente |
| Validar el objeto tras la subida | Dar por bueno lo subido |
| CORS con origen, métodos y cabeceras exactos | `AllowedOrigins: *` con cabeceras abiertas |
| Rol con permiso mínimo por prefijo | Firmar con credenciales de administrador |
| Registrar quién pidió la URL (no la URL) | Loguear la URL completa |

## 8. Límites, costos y versiones
- **Caducidad máxima:** 7 días (usuario IAM); con rol, la de la sesión *(verifica)*.
- **Costo:** firmar es gratis; pagas las solicitudes y la transferencia de S3 como siempre.
- **SDK v2:** `S3Presigner` (PUT/GET/…); el **POST prefirmado no viene en el SDK**: se firma la política a mano (ver [uso en Java](uso-en-java.md)).
- **Terraform:** CORS y política del firmante. Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
