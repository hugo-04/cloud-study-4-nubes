# Oracle OCI · Caso integrado · Subida de archivos con claim check

El equipo de catálogo de ModaLima sube fotos de 5–20 MB y los socios de Café Andino suben facturas en PDF. Los archivos **no pasan por la API ni por la cola**: van directo a Object Storage con una PAR, quedan en **cuarentena**, un evento dispara la validación y solo los aprobados pasan al prefijo definitivo; por la cola viaja únicamente la referencia.

## 1. Qué es

**Analogía:** la recepción de paquetería de un edificio. El mensajero deja la caja en la zona de recepción (cuarentena), seguridad la revisa (validación), y recién entonces la sube a la oficina (aprobados) y avisa por intercomunicador con el número de ticket (claim check).

```
 App ─(1) POST /subidas ─► API: crea registro PENDIENTE + PAR ObjectWrite "cuarentena/<id>.jpg" (10 min)
 App ─(2) PUT directo con la PAR ─► Object Storage bucket "subidas"
 Bucket ─(3) evento createobject ─► Events ─► Function "validador"
 Validador ─(4) lee 16 bytes (firma) + tamaño ─► renameObject a "aprobados/<id>.jpg" (condicional por ETag)
           ─(5) estado APROBADA + ticket {objeto, sha, bytes} ─► Queue "procesar-imagenes"
 Reconciliador (cada hora): PENDIENTE > 1 h sin objeto → EXPIRADA ; cuarentena > 1 día → borrar
```

## 2. Cómo funciona por dentro

### Estados de una subida
| Estado | Significa | Transición siguiente |
|---|---|---|
| `PENDIENTE` | PAR emitida, esperando archivo | `RECIBIDA` (evento) o `EXPIRADA` |
| `RECIBIDA` | Archivo en cuarentena | `APROBADA` o `RECHAZADA` |
| `APROBADA` | Movido a `aprobados/`, ticket enviado | `PROCESADA` |
| `RECHAZADA` | Tipo o tamaño inválido; se borra | — |
| `EXPIRADA` | Nunca llegó | — |

Cada transición es **condicional** («de `RECIBIDA` a `APROBADA` solo si sigue `RECIBIDA`»): los eventos duplicados no hacen daño.

### Qué servicio resuelve cada necesidad
| Necesidad | Servicio |
|---|---|
| Subida directa sin credenciales | [PAR](../../06-storage/par/README.md) `ObjectWrite` con nombre fijo |
| Avisar que llegó | [Eventos de Object Storage](../../06-storage/eventos-object-storage/README.md) |
| Validar | [Functions](../../04-compute/functions/README.md) |
| Mover sin copiar | `RenameObject` dentro del bucket |
| Procesar después | [Queue](../../07-mensajeria/queue/README.md) con el ticket ([claim check](../../06-storage/claim-check/README.md)) |
| Estado de cada subida | [NoSQL](../../08-datos/nosql/README.md) o la base del servicio |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Archivos de usuarios de MB a GB | **Este caso** |
| Archivos de pocos KB en un formulario | Subida a la API puede bastar |
| Archivos que deben escanearse con antivirus | Agrega el paso de escaneo antes de aprobar |
| Contenido público inmediato | **No** sin validar: primero cuarentena |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Cuarentena** | Prefijo donde nada se usa hasta validarse |
| **Firma de archivo (*magic bytes*)** | Los primeros bytes que dicen el tipo real |
| **Transición condicional** | Cambiar estado solo si está en el esperado |
| **Reconciliador** | Proceso que limpia lo que quedó a medias |

## 5. Cómo se usa
1. Bucket con eventos, regla hacia la función, cola y ciclo de vida de la cuarentena: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Validación, máquina de estados y movimiento condicional en Java: [uso en Java](uso-en-java.md).
3. Prueba manual: [`ejemplos/cli/subida.sh`](ejemplos/cli/subida.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| API de subidas | — | `PAR_MANAGE` + `OBJECT_CREATE` solo en `cuarentena/` |
| Validador (función) | — | `read objects` en cuarentena, `manage objects` para renombrar/borrar, `use queues` |
| Procesador | — | `read objects` en `aprobados/` |

- La PAR fija el nombre; el cliente no elige dónde escribe.
- Nunca confíes en la extensión ni en el `Content-Type`: valida la firma.
- Cuarentena con ciclo de vida corto.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| PAR de 10 minutos a un nombre fijo | PAR `AnyObjectWrite` al bucket |
| Validar firma y tamaño | Confiar en `.jpg` |
| Transiciones condicionales | Actualizar estado sin comprobar el anterior |
| Reconciliador | Dejar `PENDIENTE` para siempre |
| Ticket por la cola | El archivo en la cola |

## 8. Límites, costos y versiones
- **Costo:** almacenamiento + peticiones + invocaciones de la función + mensajes *(verifica)*.
- **Límites** (verifica): tamaño de una subida simple con PAR (usa multipart para archivos muy grandes), tiempo máximo de la función.
- **Terraform:** `oci_objectstorage_bucket`, `oci_events_rule`, `oci_queue_queue`, `oci_objectstorage_object_lifecycle_policy`.
- **SDK:** `ObjectStorageClient` (`renameObject`, `getObject` con rango), `QueueClient`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
