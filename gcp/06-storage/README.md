# Google Cloud · 06 Storage

¿Dónde guardo archivos, cómo los comparto y cómo reacciono cuando llegan?

| Unidad | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Cloud Storage](cloud-storage/README.md) | ¿Dónde guardo archivos durables y baratos? | Bodega de cajas con etiqueta | Comprobantes, fotos, respaldos |
| [URLs firmadas](urls-firmadas/README.md) | ¿Cómo comparto sin dar credenciales? | Código temporal de casillero | Descargas y subidas directas |
| [Filestore](filestore/README.md) | ¿Y si necesito una carpeta compartida NFS? | Carpeta compartida de la oficina | `ReadWriteMany`, CMS heredado |
| [Eventos de Cloud Storage](eventos-cloud-storage/README.md) | ¿Cómo reacciono a archivos nuevos? | El timbre con cámara | Miniaturas, indexación |
| [Claim check](claim-check/README.md) | ¿Cómo mando cargas grandes por Pub/Sub? | Guardarropa del teatro | Mensajes grandes |

## Árbol de decisión: «quiero…»

```
¿Guardar archivos y leerlos por API?                 → Cloud Storage (acceso uniforme, ciclo de vida)
   ├─ ¿Compartir con alguien sin cuenta?             → URL firmada V4 (firmada con signBlob)
   ├─ ¿Hacer algo cuando llega uno?                  → Notificación a Pub/Sub o Eventarc (dedupe por generación)
   └─ ¿Enviarlo por mensajería?                      → Claim check
¿Montar una carpeta desde muchas VMs/pods?            → Filestore
¿Es un disco de una sola VM o una base de datos?      → Persistent Disk / servicio de datos
```

## Comparativa

| Característica | Cloud Storage | Filestore |
|---|---|---|
| **Acceso** | API (JSON/XML), URLs firmadas | NFS |
| **Control de acceso a datos** | IAM | Opciones de exportación + UNIX |
| **Edición parcial** | No | Sí |
| **Cobro** | Por uso y clase | Por capacidad aprovisionada |
| **Eventos** | Sí | No |
| **Error típico** | `allUsers` | Exportación abierta |

## La receta ModaLima
| Necesidad | Pieza | Por qué |
|---|---|---|
| Comprobantes | Bucket con CMEK + `doesNotExist` + URL GET de 10 min | Idempotente y privado |
| Fotos del catálogo | URL PUT firmada → notificación → Cloud Run de miniaturas | Subida directa y procesamiento |
| Pedidos mayoristas | Claim check con Pub/Sub | Mensajes livianos |
| CMS heredado | Filestore con exportación por subred | Necesita NFS |

## Orden recomendado de adopción
1. Buckets como código con acceso uniforme y prevención pública.
2. Escrituras idempotentes y nombres deterministas.
3. URLs firmadas sin llaves.
4. Notificaciones con DLQ y consumidores idempotentes.
5. Claim check donde crezcan los mensajes.
6. Filestore solo si el software lo exige.

## Reglas transversales
- Nada público por accidente (política de organización).
- La generación identifica la versión exacta.
- Ciclo de vida desde el día uno.
- No registrar URLs firmadas ni contenido.
- Al menos una vez: deduplica.

## Java en storage: qué construye cada `uso-en-java.md`
| Unidad | Qué construyes | Patrón común |
|---|---|---|
| Cloud Storage | Guardado idempotente (`doesNotExist`) | Lógica pura + adaptador |
| URLs firmadas | Emisor con reglas y firma V4 sin llaves | `ServiceAccountSigner` |
| Filestore | Auditor de exportaciones vía Asset Inventory | Lectura de estructuras |
| Eventos | Consumidor push con dedupe por generación | Respuesta 2xx a duplicados |
| Claim check | Sobre híbrido con generación y SHA-256 | Orden de escritura |

## Cómo se relaciona con otros capítulos
- [Red](../01-red/README.md): acceso privado a las APIs y PSA para Filestore.
- [IAM](../02-iam/README.md): roles por bucket y firma con signBlob.
- [Secretos](../03-secretos/README.md): CMEK.
- [Compute](../04-compute/README.md): consumidores en Cloud Run y funciones.
- [Mensajería](../07-mensajeria/README.md): Pub/Sub.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos, troubleshooting, repaso y prompt de NotebookLM.
