# AWS · 06 Storage

Dónde viven los archivos y cómo se mueven: **S3 como almacén, las URLs prefirmadas para subir y bajar sin pasar por tu API, Claim Check para enviar referencias en lugar de archivos, los eventos de S3 como disparador y EFS cuando necesitas un sistema de archivos compartido**.

| Servicio | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Amazon S3](s3/README.md) | ¿Dónde guardo archivos de forma duradera y barata? | La bodega con casilleros etiquetados | Archivos de usuario, backups, logs, sitios estáticos, datos de analítica |
| [URLs prefirmadas](urls-prefirmadas/README.md) | ¿Cómo dejo subir o bajar un archivo sin darle credenciales a nadie? | El boleto de cine con fecha y hora | Subida/descarga directa desde navegador o app |
| [Claim Check](claim-check/README.md) | ¿Cómo muevo un archivo grande por una cola? | El guardarropa del teatro | Mensajes que no caben en SQS/SNS/Kinesis/Kafka |
| [Eventos de S3](eventos-s3/README.md) | ¿Cómo me entero de que llegó un archivo? | El timbre de la bodega | Procesar al llegar: CSV, imágenes, PDF |
| [Amazon EFS](efs/README.md) | ¿Cómo comparto una carpeta POSIX entre muchos contenedores? | La carpeta compartida de la oficina | Modelos y datos compartidos, aplicaciones heredadas |

> Se encadenan: **cliente → URL prefirmada → S3 → evento → cola (ticket) → consumidor → resultado en S3**. EFS queda aparte, para cuando S3 no encaja.

## Árbol de decisión: «quiero…»

```
¿Guardar archivos de forma duradera y barata?
   └─ S3 (privado, cifrado, versionado, con ciclo de vida)

¿Que el navegador o la app suba un archivo sin pasar por mi API?
   └─ URL prefirmada PUT (o POST con política si importa el tamaño)

¿Que un usuario descargue un archivo privado un rato?
   └─ URL prefirmada GET (5 minutos) — o CloudFront con URLs firmadas si hay mucho tráfico

¿Enviar un archivo grande (o su procesamiento) por una cola o tópico?
   └─ Claim Check: sube a S3 y envía el ticket

¿Procesar un archivo en cuanto llega?
   └─ Evento de S3 → SQS (con DLQ) → consumidor idempotente

¿Muchos consumidores o filtros por tamaño/motivo?
   └─ Eventos de S3 hacia EventBridge

¿Carpeta compartida con permisos POSIX entre contenedores o Lambda?
   └─ EFS con puntos de acceso

¿Servir un sitio estático?
   └─ S3 privado + CloudFront con OAC

¿Una base de datos o un disco para una sola instancia?
   └─ Ni S3 ni EFS: base de datos o EBS
```

## Comparativa

| Característica | S3 | EFS |
|---|---|---|
| **Modelo** | Objetos (clave → datos) vía API HTTP | Archivos y directorios POSIX vía NFS |
| **Acceso concurrente** | Ilimitado; cada PUT reemplaza el objeto entero | Muchos clientes; lecturas/escrituras parciales y bloqueos NFS |
| **Latencia** | Decenas de ms por solicitud | ms por operación sobre red |
| **Escala** | Prácticamente ilimitada | Elástica (petabytes), por sistema de archivos |
| **Quién lo monta** | Nadie: se usa por API/SDK | EC2, ECS, EKS, Lambda |
| **Costo típico por GB** | Más bajo | Más alto (Standard); IA/Archive lo reducen |
| **Eventos nativos** | Sí | No (usa S3 o tu aplicación) |
| **Caso típico** | Archivos de usuario, datos, backups | Modelos compartidos, apps heredadas |
| **Error típico** | Bucket público, versiones sin ciclo de vida | Sonda sin timeout, todos montando la raíz |

## La receta ModaLima (cómo se ve junto)

| Pieza | Qué se configura |
|---|---|
| **Bucket de comprobantes** | Privado, cifrado con KMS y Bucket Key, versionado, ciclo de vida (IA a 30 días, versiones viejas a 60), política que niega HTTP |
| **Subidas del cliente** | URL prefirmada PUT de 10 minutos con `Content-Type` firmado; POST con límite de tamaño para fotos |
| **Procesamiento de catálogos grandes** | Claim Check: ticket con `versionId` + SHA-256 en SQS, consumidor idempotente con DynamoDB, DLQ con alarma |
| **Llegada de CSV de proveedores** | Evento `ObjectCreated` en `entrada/` → SQS; resultados en `salida/` (nunca en el prefijo del evento) |
| **Exportes** | EventBridge con patrón (prefijo `exportes/`, tamaño > 0) hacia varios consumidores |
| **Modelo de recomendaciones** | EFS con punto de acceso de solo lectura, montado en Lambda |

## Orden recomendado de adopción
1. **Bucket seguro**: Block Public Access, cifrado, versionado, política TLS (S3).
2. **Subidas directas** con URL prefirmada y validación posterior.
3. **Eventos de S3 → SQS + DLQ** con consumidor idempotente.
4. **Claim Check** para lo que no quepa en un mensaje.
5. **Ciclo de vida** y clases de almacenamiento según uso real.
6. **EventBridge** cuando haya varios consumidores o filtros finos.
7. **EFS** solo si hay un requisito POSIX real.
8. **Todo como código** (capítulo 10, Terraform en AWS).

## Reglas transversales
- **Todo privado por defecto;** lo público es una decisión explícita (y casi siempre pasa por CloudFront).
- **El backend decide la clave**, el tipo y el tamaño permitidos; el cliente no.
- **Subir primero, publicar después;** el consumidor valida el ticket y el objeto (`versionId` + SHA-256).
- **Toda entrega es «al menos una vez»:** consumidores idempotentes.
- **Entrada y salida en prefijos distintos** para evitar bucles de eventos.
- **Retención del objeto mayor que la de la DLQ.**
- **Cifrado y TLS siempre;** con KMS, permisos en el rol **y** en la clave.
- **El ciclo de vida es parte del diseño,** no un extra: versiones, multiparte incompleta, temporales.

## Java en este capítulo: qué hace cada `uso-en-java.md`

| Servicio | Qué construyes desde Java | Patrón común |
|---|---|---|
| S3 | Claves seguras, plan de partes, checksum SHA-256, subir/bajar/listar, escrituras condicionales | Núcleo puro + `S3Client` / `S3AsyncClient` |
| URLs prefirmadas | Política de subida, caducidad efectiva, nombre de descarga, firma PUT/GET con `S3Presigner` y **POST firmado a mano** | Núcleo puro + `S3Presigner` |
| Claim Check | Ticket, validación, idempotencia (DynamoDB condicional), productor, consumidor, poller de SQS | Núcleo puro + S3/SQS/DynamoDB |
| Eventos de S3 | Lector JSON propio, normalización de notificaciones/EventBridge/SNS, filtro anti-recursión, deduplicación y orden por `sequencer`, manejador de Lambda con fallos parciales | Núcleo puro sobre `Map` |
| EFS | Rutas seguras, escritura atómica, bloqueos, sonda con timeout, auditoría con el SDK | `java.nio` + `EfsClient` |

Reglas comunes: **funciones puras** para las decisiones (se prueban sin red), SDK con `close()` administrado por el contenedor, y en reactivo lo bloqueante (SDK síncrono, E/S de archivos) va a `boundedElastic` / pool de trabajadores de Mutiny.

## Cómo se relacionan con otros capítulos
- [Red](../01-red/README.md): endpoints de S3 y mount targets de EFS en subredes privadas.
- [IAM](../02-iam/README.md): roles del productor, consumidor y firmante de URLs.
- [Secretos](../03-secretos/README.md): claves de KMS para cifrar buckets, colas y EFS.
- [Compute](../04-compute/README.md): ECS, EKS y Lambda montan EFS y consumen eventos.
- [Ingress y API](../05-ingress-api/README.md): CloudFront con OAC delante de S3; URLs firmadas del borde.
- [Mensajería](../07-mensajeria/README.md): SQS, SNS, EventBridge y Kafka transportan los tickets.
- [Datos](../08-datos/README.md): DynamoDB para la idempotencia.
- [Terraform en AWS](../10-terraform/README.md): todo lo anterior como código.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos (CLI, Terraform, JSON/YAML), troubleshooting, repaso y prompt de NotebookLM.
