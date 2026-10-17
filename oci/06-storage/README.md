# Oracle OCI · 06 Storage

¿Dónde guardo archivos y cómo los comparto o reacciono a ellos? Dos almacenes (objetos y NFS) y tres formas de usarlos bien.

| Unidad | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Object Storage](object-storage/README.md) | ¿Dónde guardo archivos de forma barata y durable? | Una bodega de cajas con etiqueta | Fotos, comprobantes, respaldos, *data lake* |
| [PAR](par/README.md) | ¿Cómo comparto un archivo sin dar credenciales? | El código temporal de un casillero | Descargas y subidas directas, socios |
| [File Storage](file-storage/README.md) | ¿Y si mi software espera una carpeta compartida? | La carpeta compartida de la oficina | NFS, `ReadWriteMany`, aplicaciones heredadas |
| [Eventos de Object Storage](eventos-object-storage/README.md) | ¿Cómo reacciono cuando llega un archivo? | El timbre con cámara | Miniaturas, avisos, procesamiento |
| [Claim check](claim-check/README.md) | ¿Cómo mando por una cola algo que no cabe? | El guardarropa del teatro | Mensajes grandes |

## Árbol de decisión: «quiero…»

```
¿Guardar archivos para leerlos por API (fotos, PDF, respaldos)?
   └─ Object Storage (bucket privado, ciclo de vida, versionado)
       ├─ ¿Compartirlos con alguien sin cuenta?         → PAR corta, un objeto
       ├─ ¿Hacer algo cada vez que llega uno?          → Eventos del bucket + regla
       └─ ¿Mandarlos por una cola de mensajes?         → Claim check

¿Mi aplicación necesita montar una carpeta y la usan varias máquinas o pods?
   └─ File Storage (export options estrictas, snapshots)

¿Es un disco de un solo servidor o una base de datos?
   └─ Block Volume o un servicio de datos (no este capítulo)
```

## Comparativa

| Característica | Object Storage | File Storage |
|---|---|---|
| **Acceso** | API HTTP (SDK, CLI, PAR) | Montaje NFS |
| **Control de acceso a datos** | IAM por bucket/objeto | Export options (CIDR, squash) + UNIX |
| **Edición parcial** | No (se reemplaza el objeto) | Sí |
| **Escala** | Prácticamente ilimitada | Crece solo, rendimiento según uso |
| **Niveles de costo** | Standard / Infrequent / Archive | Uno |
| **Eventos** | Sí | No |
| **Error típico** | Bucket público | Export `0.0.0.0/0` sin squash |

## La receta ModaLima
| Necesidad | Pieza | Por qué |
|---|---|---|
| Comprobantes PDF de pedidos | Object Storage con nombre determinista + PAR de 10 min para descargar | Idempotente y sin exponer el bucket |
| Fotos subidas por el equipo de catálogo | PAR de escritura → bucket → evento → función de miniaturas | Subida directa y procesamiento automático |
| Pedidos mayoristas por la cola | Claim check | Superan el tamaño de mensaje |
| CMS heredado que escribe en disco | File Storage con export RW solo desde su subred | Necesita una carpeta |
| Respaldos | Object Storage + Archive a los 30 días | Costo |

## Orden recomendado de adopción
1. Buckets privados como código, con ciclo de vida y cifrado.
2. Escrituras idempotentes (`If-None-Match`) y nombres deterministas.
3. PAR emitidas por el backend para compartir.
4. Eventos con consumidores idempotentes.
5. Claim check donde los mensajes crezcan.
6. File Storage solo donde el software lo exija.

## Reglas transversales
- Nada público: compartir es PAR o un backend que valida.
- Puerta de servicios para llegar desde subredes privadas.
- Ciclo de vida y snapshots desde el primer día.
- Nunca registres contenido ni URLs de PAR.
- Al menos una vez: deduplica y sé idempotente.

## Java en storage: qué construye cada `uso-en-java.md`
| Unidad | Qué construyes | Patrón común |
|---|---|---|
| Object Storage | Guardado idempotente con nombre determinista e `If-None-Match` | Núcleo puro + adaptador del SDK |
| PAR | Emisor con reglas de prefijo, operación y vencimiento | Validar antes de delegar |
| File Storage | Auditor de export options | Resumen del SDK → reglas puras |
| Eventos | Consumidor que filtra, deduplica y hace `HEAD` | Idempotencia |
| Claim check | Sobre híbrido con SHA-256 + Queue | Orden de escritura |

## Cómo se relaciona con otros capítulos
- [Red](../01-red/README.md): puerta de servicios y NSG de mount targets.
- [IAM](../02-iam/README.md): políticas por bucket y permisos de PAR.
- [Secretos](../03-secretos/README.md): cifrado con llave propia.
- [Compute](../04-compute/README.md): funciones que reaccionan a eventos; volúmenes en OKE.
- [Mensajería](../07-mensajeria/README.md): colas y streams del claim check y los eventos.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos, troubleshooting, repaso y prompt de NotebookLM.
