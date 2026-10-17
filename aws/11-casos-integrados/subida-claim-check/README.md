# AWS · Caso integrado · Subida de archivos con Claim Check

Café Andino recibe **boletas, fotos y planillas** de sus tiendas. Los archivos no pasan por la API ni por la cola: el navegador los sube **directo a S3** con una URL de un solo uso, y por las colas solo viaja un **ticket** (el identificador). Este caso une S3, URLs prefirmadas, EventBridge, SQS y DynamoDB, y sobre todo enseña a **no confiar en lo que sube el público**.

## 1. Qué es

**Analogía:** una lavandería con casillero. El cliente (navegador) pide un *ticket* al mostrador (API); con él deja su bolsa en un **casillero de cuarentena** (S3) sin entrar a la tienda. Un empleado (validador) revisa la bolsa —¿es lo que dijo?, ¿cabe?, ¿no huele raro?— y solo entonces la pasa al **estante limpio** (bucket de validadas). El ticket indica en cada momento en qué estado va.

```
 Navegador ──1 POST /cargas──► API (ECS) ──► DynamoDB: carga PENDIENTE
     │   ◄── URL prefirmada PUT (5 min, tipo y tamaño firmados) ──┘
     │
     └─2 PUT archivo ─────────► S3 cuarentena  entrada/{idCarga}
                                   │ evento "Object Created"
                                   ▼
                              EventBridge (regla) ─► SQS validación (+ DLQ)
                                                          │
                                  Validador (ECS) ◄───────┘
                      3. HEAD + primeros bytes (firma del archivo) + tamaño
                      4a. OK  → copia a S3 validadas archivos/{id} → VALIDADO → borra de cuarentena
                      4b. MAL → RECHAZADO (motivo) → borra de cuarentena
     Reconciliador (cada minuto): PENDIENTE vencido → EXPIRADO (o revalida si el objeto existe) · SUBIDO atascado → revalida
     Descarga: GET /cargas/{id}/descarga → URL prefirmada GET (5 min) solo para su dueño y si está VALIDADO
```

## 2. Cómo funciona por dentro

| # | Paso | Detalle que importa |
|---|---|---|
| 1 | Se pide permiso de subir | La API valida tipo y tamaño **declarados**, crea la carga `PENDIENTE` y firma una URL PUT de 5 minutos |
| 2 | El navegador sube directo a S3 | La URL firma `Content-Type` y `Content-Length`: otro tipo o tamaño → `403 SignatureDoesNotMatch` |
| 3 | S3 avisa a EventBridge | El bucket tiene `eventbridge = true`; la regla filtra el prefijo `entrada/` |
| 4 | SQS entrega al validador | Cola propia + DLQ; el aviso puede repetirse o perderse |
| 5 | El validador comprueba la realidad | Tamaño real, y la **firma del archivo** (primeros bytes) contra el tipo declarado |
| 6 | Promoción | Copia a `validadas`, transición `SUBIDO → VALIDADO` condicional, y recién entonces se borra la cuarentena |
| 7 | Reconciliación | Si el aviso se perdió, el estado `PENDIENTE` viejo se contrasta con S3 |
| 8 | Descarga | URL prefirmada GET de 5 minutos, solo al dueño, solo si `VALIDADO` |

| Necesidad | Servicio | Capítulo |
|---|---|---|
| Guardar archivos grandes sin pasar por la API | S3 + URLs prefirmadas | [06](../../06-storage/urls-prefirmadas/README.md) |
| El ticket en lugar del archivo | Claim Check | [06](../../06-storage/claim-check/README.md) |
| Enterarse de la subida | Eventos de S3 → EventBridge | [06](../../06-storage/eventos-s3/README.md) · [07](../../07-mensajeria/eventbridge/README.md) |
| Cola de validación con reintentos | SQS | [07](../../07-mensajeria/sqs/README.md) |
| Estado de cada carga | DynamoDB | [08](../../08-datos/dynamodb/README.md) |
| Permisos mínimos | IAM / roles de tarea | [02](../../02-iam/iam-roles-politicas/README.md) |
| Todo como código | Terraform | [10](../../10-terraform/README.md) |

### La máquina de estados

```
 PENDIENTE ──subió──► SUBIDO ──ok──► VALIDADO
     │                   └──mal──► RECHAZADO
     └──venció la URL sin subir──► EXPIRADO          (VALIDADO, RECHAZADO y EXPIRADO son finales)
```
Cada cambio es una **escritura condicional** (`estado = :de`): si dos procesos intentan lo mismo, solo uno gana y el otro lo nota.

## 3. Para qué sirve y cuándo NO

- **Sirve** para: boletas, fotos de productos, planillas, cualquier archivo que el público o los socios suben.
- **No** hace falta si los archivos son pequeños (< 1 MB) y solo los suben usuarios internos de confianza: un `PutObject` desde el servicio puede bastar. Tampoco reemplaza a un antivirus: aquí se valida **forma**, no contenido malicioso (ver «Qué NO hacer»).

## 4. Conceptos clave (en palabras simples)

- **Claim Check:** dejas la carga pesada en un depósito y por el canal solo envías el «ticket» para recogerla.
- **URL prefirmada:** enlace temporal que permite una acción concreta sobre un objeto concreto, firmado con los permisos de quien lo generó.
- **Cuarentena:** zona donde nada es confiable hasta ser revisado.
- **Firma del archivo (magic bytes):** los primeros bytes que identifican el formato (`%PDF-`, `PNG`, `PK`…). Se compara con lo que el cliente dijo.
- **Escritura condicional:** «cambia el estado solo si todavía es X».
- **Reconciliador:** tarea que compara lo que *debería* haber pasado con lo que pasó y repara.

## 5. Cómo se usa

1. Crea la infraestructura con [`ejemplos/terraform`](ejemplos/terraform/main.tf).
2. La API implementa `POST /cargas`, `GET /cargas/{id}` y `GET /cargas/{id}/descarga` (ver [uso en Java](uso-en-java.md)).
3. El validador consume la cola; el reconciliador corre cada minuto.
4. Prueba con [`ejemplos/cli/prueba-de-subida.sh`](ejemplos/cli/prueba-de-subida.sh); los formatos están en [`ejemplos/json`](ejemplos/json/).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Pipeline de Terraform | Crea buckets, tabla, cola, reglas | — |
| API de solicitudes (rol de tarea) | — | `s3:PutObject` sobre `entrada/*` (solo para **firmar**), `s3:GetObject` sobre `archivos/*` (para firmar), `dynamodb:PutItem/GetItem` |
| Validador (rol de tarea) | — | Leer/borrar `entrada/*`, escribir `archivos/*`, su cola, `dynamodb:GetItem/UpdateItem/Query` |
| Navegador | — | Solo la URL prefirmada (una acción, un objeto, 5 minutos) |

- Buckets con bloqueo de acceso público, cifrado y política que **exige TLS**.
- La clave del objeto es el `idCarga` (no el nombre del cliente): evita `../`, colisiones y datos personales en claves.
- El dueño se comprueba **en cada descarga**; un id ajeno responde como si no existiera.

## 7. Qué hacer / qué NO hacer

| Haz | No hagas |
|---|---|
| Firmar `Content-Type` y `Content-Length` | Aceptar «cualquier cosa» y validar después |
| Subir a un bucket de **cuarentena** y promover | Subir directo al bucket de producción |
| Validar la firma del archivo, no solo la extensión | Confiar en el nombre o en el `Content-Type` que declara el cliente |
| Borrar de cuarentena **después** de la transición | Borrar antes: un reintento ya no encuentra el objeto |
| Reconciliar periódicamente | Asumir que el evento siempre llega |
| URL de descarga corta y por dueño | Un enlace público permanente |
| Regla de ciclo de vida que limpia la cuarentena | Dejar basura acumulándose |
| Pasar el archivo por un antivirus/escáner si el riesgo lo exige | Creer que los *magic bytes* detectan malware |

## 8. Límites, costos y versiones

- `PutObject` de una sola operación hasta 5 GiB; para más, multipart *(verifica)*.
- La URL expira a los 5 minutos *(configurable; máximo depende de las credenciales que firman)*.
- Costos: solicitudes de S3 y almacenamiento; EventBridge y SQS por evento; DynamoDB bajo demanda *(verifica precios)*.
- Versiones del código: Java 21, Spring Boot 4.1.x, Quarkus 3.40.x, AWS SDK v2.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
