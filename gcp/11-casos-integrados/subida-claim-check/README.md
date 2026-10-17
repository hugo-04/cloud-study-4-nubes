# Google Cloud · Caso integrado · Subida de archivos con claim check

Los clientes mayoristas de ModaLima suben catálogos (PDF) y fotos (JPEG/PNG) de hasta 25 MB. El flujo: **URL firmada de subida directa** a una zona de **cuarentena**, **validación** por la firma del archivo, **paso a aprobados** con precondiciones y un **mensaje liviano** (el ticket del claim check) a quien procesa. Nada pasa por los servidores de la app y nada sin validar llega a producción.

## 1. Qué es

**Analogía:** la recepción de paquetes de una empresa: el mensajero deja el paquete en la sala de cuarentena (no entra al edificio), seguridad lo revisa por rayos X (firma de bytes) y, si está bien, lo pasa al almacén y deja una nota en el buzón del destinatario con la ubicación.

```
 App ─ POST /subidas → Cloud Run "subidas": URL firmada V4 PUT (10 min) a gs://modalima-subidas/cuarentena/S-123.pdf
 Navegador ─ PUT directo ─► bucket modalima-subidas (cuarentena/ con ciclo de vida 1 día)
                               │ notificación OBJECT_FINALIZE → Pub/Sub "subidas-llegadas"
                               ▼
                         Cloud Run "validador" (push OIDC)
                           · lee 16 bytes (rango) · valida firma y tamaño
                           · copia a aprobados/ con ifGenerationMatch + doesNotExist · borra el original
                           · ticket {bucket, objeto, generación, sha256} → Pub/Sub "subidas-aprobadas"
                         Rechazado → se borra (con ifGenerationMatch) y se registra el motivo
```

## 2. Cómo funciona por dentro

| Paso | Pieza | Detalle |
|---|---|---|
| 1 | URL firmada | `signBlob` de la SA (sin llaves), método PUT, `Content-Type` fijado |
| 2 | Cuarentena | Prefijo `cuarentena/` con ciclo de vida de 1 día y sin lectores |
| 3 | Evento | Notificación de Cloud Storage a Pub/Sub (`OBJECT_FINALIZE`) |
| 4 | Estado | Máquina de estados con transición condicional (dedupe del evento) |
| 5 | Validación | Primeros bytes (firma) + tamaño, nunca la extensión |
| 6 | Paso a aprobados | Copia con precondiciones de generación y borrado del original |
| 7 | Ticket | Mensaje pequeño con generación y hash |

| Necesidad | Servicio | Capítulo |
|---|---|---|
| Subida directa | URL firmada | [06](../../06-storage/urls-firmadas/README.md) |
| Evento de llegada | Notificación a Pub/Sub | [06](../../06-storage/eventos-cloud-storage/README.md) |
| Ticket | Claim check | [06](../../06-storage/claim-check/README.md) |
| Validador | Cloud Run | [04](../../04-compute/cloud-run/README.md) |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Archivos de usuarios externos | Este patrón |
| Archivos internos de confianza | Subida directa a aprobados con eventos |
| Archivos > 5 GB | Subida reanudable *(verifica límites)* |
| Antivirus requerido | Agrega un escaneo en el paso de validación |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Cuarentena** | Zona sin lectores donde caen las subidas |
| **Firma (magic bytes)** | Bytes iniciales que identifican el tipo real |
| **Generación** | Versión exacta del objeto; base de las precondiciones |
| **Transición condicional** | Cambiar de estado solo desde el esperado |
| **Ticket** | Mensaje con la ubicación, no con el archivo |

## 5. Cómo se usa
1. Bucket, ciclo de vida, notificación y permisos: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Validador y movimiento con precondiciones en [Java](uso-en-java.md).
3. Prueba: [`ejemplos/cli/subida.sh`](ejemplos/cli/subida.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| `run-subidas` | — | `iam.serviceAccountTokenCreator` sobre sí misma (signBlob); crea objetos en `cuarentena/` vía la URL |
| `run-validador` | — | `storage.objectUser` en el bucket, `pubsub.publisher` en `subidas-aprobadas` |
| Procesadores | — | `storage.objectViewer` (con condición sobre `aprobados/`) |

- URL con método, tipo y vencimiento fijos; nunca registrada en logs.
- Condiciones de IAM por prefijo: nadie lee la cuarentena.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Validar por bytes | Confiar en la extensión o el `Content-Type` |
| Precondiciones de generación | Copiar y borrar «a ciegas» |
| Ciclo de vida en cuarentena | Dejar basura acumulándose |
| Ticket con hash y generación | Mandar el archivo por Pub/Sub |
| Dedupe del evento | Procesar dos veces el mismo objeto |

## 8. Límites, costos y versiones
- **Costo:** almacenamiento, operaciones y Pub/Sub; mínimo *(verifica)*.
- **Límites** (verifica): tamaño de objeto, vigencia máxima de URL firmada V4 (7 días).
- **Terraform:** `google_storage_bucket`, `google_storage_notification`, `google_pubsub_topic`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
