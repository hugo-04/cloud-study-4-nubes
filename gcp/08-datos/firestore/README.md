# Google Cloud · Datos · Firestore

Base de datos de **documentos** sin servidor: colecciones de documentos JSON-like con subcolecciones, consultas indexadas, transacciones, **escuchas en tiempo real** y SDK para móviles y web con reglas de seguridad. Escala sola y cobra por operación. Tiene modo **nativo** (el recomendado) y modo **Datastore** (compatibilidad) *(verifica)*.

## 1. Qué es

**Analogía:** un archivador de fichas: cada cajón es una colección, cada ficha un documento con campos, y una ficha puede tener su propio mini-cajón (subcolección). El archivador avisa a quien esté mirando cuando una ficha cambia.

```
 Base "(default)" en southamerica-east1 (o multirregión nam5/eur3)
   └── clientes/{clienteId}                 {nombre, nivel, puntos}
         └── carritos/{carritoId}           {items[], total, actualizado}
   └── contadores/visitas/fragmentos/{0..9} {n}
 Índices: simples automáticos · compuestos declarados · TTL por campo
 Clientes: SDK de servidor (IAM) · SDK móvil/web (reglas de seguridad)
```

## 2. Cómo funciona por dentro

| Pieza | Qué es |
|---|---|
| **Documento** | Hasta 1 MiB, campos tipados, identificado por ruta |
| **Colección / subcolección** | Agrupación sin esquema |
| **Índices** | Todos los campos simples indexados; compuestos para consultas combinadas |
| **Transacciones** | Optimistas en servidor; hasta 500 escrituras *(verifica)* |
| **Escuchas** | Notificación de cambios en tiempo real |
| **TTL** | Borrado automático por un campo de fecha |
| **PITR y respaldos** | Recuperación a un instante y respaldos programados |
| **Ediciones** | Standard y Enterprise (compatibilidad MongoDB) *(verifica)* |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Carritos, perfiles, preferencias de app móvil | Firestore |
| Datos jerárquicos con lectura por documento | Firestore |
| Reportes con joins y agregaciones complejas | [Cloud SQL](../cloud-sql/README.md) o BigQuery |
| Millones de escrituras por segundo de telemetría | [Bigtable](../bigtable/README.md) |
| Inventario global con transacciones grandes | [Spanner](../spanner/README.md) |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Ruta** | `coleccion/doc/subcoleccion/doc` |
| **Índice compuesto** | Necesario para filtrar/ordenar por varios campos |
| **Contador distribuido** | Repartir un contador en fragmentos para escribir más rápido |
| **Reglas de seguridad** | Autorización para clientes móviles/web |
| **Punto caliente** | Un documento o rango de IDs secuenciales muy escrito |

## 5. Cómo se usa
1. Base, índice compuesto, TTL y acceso: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Contador distribuido y transacción de carrito en [Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/firestore.sh`](ejemplos/cli/firestore.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `roles/datastore.owner` | — |
| Backend | — | `roles/datastore.user` |
| Reportes | — | `roles/datastore.viewer` |
| Apps móviles | — | Reglas de seguridad + autenticación de usuarios |

- El SDK de servidor **ignora** las reglas de seguridad: el control es IAM.
- CMEK opcional *(verifica)*; *delete protection* en la base.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| IDs automáticos (aleatorios) | IDs secuenciales o con fecha al inicio |
| Contadores distribuidos para lo muy escrito | Un documento actualizado cientos de veces por segundo |
| Índices como código | Crear índices desde el enlace del error en producción |
| TTL para datos temporales | Jobs de borrado manuales |
| Documentos pequeños | Arreglos que crecen sin límite |

## 8. Límites, costos y versiones
- **Costo:** por lectura, escritura y borrado de documento, almacenamiento y salida; capa gratuita diaria *(verifica)*.
- **Límites** (verifica): 1 MiB por documento, ~1 escritura sostenida por segundo por documento, 500 escrituras por transacción/lote.
- **Terraform:** `google_firestore_database`, `google_firestore_index`, `google_firestore_field`.
- **Java:** `google-cloud-firestore` (Spring Cloud GCP tiene integración reactiva).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
