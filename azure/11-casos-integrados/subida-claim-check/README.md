# Azure · Caso integrado · Subida de archivos con Claim Check

Café Andino permite que sus proveedores suban **facturas en PDF y fotos de lotes de café** desde el celular. El archivo no debe pasar por la API (sería lento y caro), no debe usarse hasta comprobar que es lo que dice ser, y los demás sistemas deben enterarse sin cargar con megabytes en cada mensaje. Este caso une cuatro piezas de Azure en un flujo con **estados explícitos**.

## 1. Qué es

**Analogía:** un buzón de paquetería con **zona de revisión**. El proveedor recibe una llave que abre *una sola casilla* durante diez minutos y deja su paquete (SAS). Nadie usa el paquete todavía: un revisor lo abre en la zona de revisión (cuarentena), comprueba que lo que hay dentro es lo que dice la etiqueta y recién entonces lo pasa al almacén (validados). Al resto de la empresa solo se le entrega **el comprobante de recibo** (el *ticket* del Claim Check) con la ubicación del paquete.

```
 App ──1 pide permiso──► API ──► fila PENDIENTE + SAS(10 min, 1 blob, solo escribir)
 App ══2 sube los bytes directo══► Blob «cuarentena»        (la API nunca ve el archivo)
                                       │ BlobCreated
                              Event Grid ► cola ► Validador ──► mal: RECHAZADA, se borra
                                                       │ bien: copia a «validados» + VALIDADA
                                                       ▼
                              bandeja de salida ► Service Bus (ticket) ► procesadores ► PROCESADA
 Conciliador: PENDIENTE vieja → EXPIRADA · SUBIDA atascada → revalidar · cuarentena > 1 día → se borra sola
```

## 2. Cómo funciona por dentro

| # | Paso | Quién | Detalle que importa |
|---|---|---|---|
| 1 | Pedir permiso de subida | App → API | Indica tipo y tamaño. La API valida contra la política y **registra la fila antes** de firmar |
| 2 | Obtener la SAS | API | SAS de **delegación de usuario** (firmada con Entra ID, no con la clave de la cuenta): un blob, crear/escribir, 10 min |
| 3 | Subir directo a Blob | App → Blob | `PUT` con `x-ms-blob-type: BlockBlob`; CORS permitido solo para el origen de la app |
| 4 | Evento «blob creado» | Event Grid → cola | Filtro por contenedor `cuarentena`; la cola absorbe picos y permite reintentos |
| 5 | Validar | Validador | Tamaño, **tipo real por bytes iniciales**, hash; estado `SUBIDA` → `VALIDADA` o `RECHAZADA` |
| 6 | Mover a «validados» | Validador | Copia dentro de la cuenta; la copia es el único archivo que el negocio ve |
| 7 | Avisar | Bandeja de salida → Service Bus | Ticket con ruta, tamaño y hash, no el archivo |
| 8 | Procesar | Consumidores | Leen de `validados`; al terminar, `PROCESADA` |
| 9 | Limpiar | Política de ciclo de vida + conciliador | Lo abandonado se expira y se borra solo |

**Por qué cuarentena:** cualquiera con una SAS puede subir *cualquier cosa* con *cualquier nombre*; solo después de revisar se mueve a un lugar de confianza.
**Por qué estados en una tabla:** el blob guarda bytes, no historia. La tabla `subidas` ([esquema](ejemplos/sql/esquema.sql)) responde «¿en qué paso está el archivo de Juan?» y evita duplicados con transiciones condicionadas al estado actual.

### Servicios que intervienen

| Pieza | Servicio | Capítulo |
|---|---|---|
| Archivos | Blob Storage (contenedores `cuarentena` y `validados`) | [06](../../06-storage/blob-storage/README.md) |
| Permiso temporal | SAS tokens (delegación de usuario) | [06](../../06-storage/sas-tokens/README.md) |
| Referencia en lugar de archivo | Claim Check | [06](../../06-storage/claim-check/README.md) |
| Aviso de creación | Eventos de blob (Event Grid + cola) | [06](../../06-storage/eventos-blob/README.md) · [07](../../07-mensajeria/event-grid/README.md) |
| Cola de eventos | Storage Queues | [07](../../07-mensajeria/storage-queues/README.md) |
| Aviso a otros equipos | Service Bus | [07](../../07-mensajeria/service-bus/README.md) |
| Estado y bandeja de salida | Azure SQL / PostgreSQL | [08](../../08-datos/azure-sql/README.md) |
| Identidades | Managed Identity / Workload Identity | [02](../../02-iam/workload-identity/README.md) |
| Infraestructura | Terraform | [10](../../10-terraform/README.md) |

## 3. Para qué sirve y cuándo NO

| Situación | ¿Este patrón? | Alternativa |
|---|---|---|
| Fotos o PDF de 1–100 MB desde móviles | ✅ | — |
| Archivos de cientos de MB o GB | ✅ con subida por bloques | Subida por bloques desde el SDK del cliente |
| Un adjunto de 20 KB | ⚠️ Excesivo | Guardarlo en la base o enviarlo por la API |
| Se necesita antivirus o análisis profundo | ✅ añade un paso | Un escáner antes de pasar a `VALIDADA` (servicio de seguridad que elijas) |
| Contenido que **nunca** debe salir de la red privada | ⚠️ | Subida desde dentro de la VNet; el navegador público no puede usar este camino |
| Se necesita saber *quién* subió y cuándo, con trazabilidad legal | ✅ | La tabla `subidas` + inmutabilidad en el contenedor si la norma lo exige |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Claim Check** | Guardar lo pesado aparte y circular solo un «comprobante» con su ubicación |
| **SAS de delegación de usuario** | Enlace firmado con una identidad de Entra ID; se puede revocar y no expone la clave de la cuenta |
| **Cuarentena** | Zona donde aterriza todo lo no confiable; nada sale de ahí sin revisión |
| **Bytes mágicos** | Los primeros bytes de un archivo que revelan su tipo real (`%PDF-`, `\x89PNG`, `FF D8 FF`) |
| **Máquina de estados** | Lista de estados y de saltos permitidos; lo demás se rechaza |
| **Control optimista** | `update … where estado = ?`: si otro ya lo movió, no se hace nada |
| **Conciliador** | Tarea periódica que arregla lo que quedó a medias |
| **Ciclo de vida** | Regla de la cuenta que mueve o borra blobs por edad |

## 5. Cómo se usa

1. **Terraform** ([`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf)): cuenta sin clave compartida, contenedores, CORS, política de limpieza, tópico y suscripción de Event Grid hacia una cola, roles mínimos.
2. **Esquema** ([`ejemplos/sql/esquema.sql`](ejemplos/sql/esquema.sql)) y política de archivos (tipos y tamaño máximo).
3. **API**: `POST /api/subidas` devuelve `{id, url, cabeceras, vence}`; el cliente hace `PUT` a esa URL.
4. **Validador** con la cola; **conciliador** cada 5 minutos.
5. **Operación**: [`inspeccionar-subidas.sh`](ejemplos/cli/inspeccionar-subidas.sh) y [consultas KQL](ejemplos/kql/kql-subidas.md). Formato del evento: [`evento-blob-creado.json`](ejemplos/json/evento-blob-creado.json); del ticket: [`ticket-validada.json`](ejemplos/json/ticket-validada.json).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Pipeline de Terraform | Contributor + RBAC Administrator acotado | — |
| **API de subidas** | — | *Storage Blob Delegator* (cuenta) + datos en `cuarentena` (una SAS de delegación hereda los permisos del que firma) |
| **Validador** | — | Datos en `cuarentena` y `validados`; *Storage Queue Data Message Processor* en la cola |
| **Event Grid (identidad del tópico)** | — | *Storage Queue Data Message Sender* en la cuenta |
| **Procesadores** | — | *Storage Blob Data Reader* en `validados` |
| Operaciones | Reader | Lector de datos solo si lo necesitan |

| Amenaza | Defensa |
|---|---|
| Subir un ejecutable renombrado `.pdf` | Tipo por bytes mágicos + lista blanca |
| Enlace filtrado | Vigencia de 10 min, un solo blob, solo escritura |
| Llenar la cuenta con basura | Tope de tamaño, cuota por usuario en la API, limpieza de cuarentena |
| Sobrescribir el archivo de otro | Ruta con UUID generado por el servidor, nunca por el cliente |
| Archivo cambiado después de validar | Se valida y se **copia**; el negocio solo lee la copia con su hash |
| Clave de la cuenta robada | `shared_access_key_enabled = false` |

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Generar el nombre del blob en el servidor | Aceptar el nombre que manda el cliente |
| Registrar la subida **antes** de entregar la SAS | Firmar primero y registrar «si llega» |
| Validar por bytes, tamaño y hash | Confiar en la extensión o el `Content-Type` del cliente |
| Cuarentena aparte y limpieza automática | Subir directo al contenedor que lee el negocio |
| Transiciones condicionadas al estado | Actualizar el estado sin condición |
| CORS solo para tus orígenes y métodos necesarios | `*` en orígenes |
| Reintentar el validador sin miedo (es repetible) | Una validación que no se puede ejecutar dos veces |

## 8. Límites, costos y versiones
- Las **SAS de delegación** duran como máximo lo que permita la clave de delegación (verifica el tope vigente en la doc oficial).
- Event Grid entrega **al menos una vez** y sin orden garantizado: por eso las transiciones son idempotentes.
- El tamaño máximo de un `PUT` único depende de la versión de la API; para archivos grandes sube por bloques (verifica los límites).
- **Costos:** transacciones y almacenamiento (barato), eventos (muy barato), la copia a `validados` duplica temporalmente el espacio; cuarentena se limpia en un día.
- Versiones del ejemplo: Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
