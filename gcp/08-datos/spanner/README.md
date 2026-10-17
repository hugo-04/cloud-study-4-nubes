# Google Cloud · Datos · Spanner

Base de datos **relacional distribuida** con **consistencia fuerte** (externa) y escala horizontal: SQL (dialecto GoogleSQL o PostgreSQL), transacciones ACID entre filas y regiones, y capacidad que se agrega en **unidades de procesamiento** sin particionar a mano. El reloj **TrueTime** es lo que permite ordenar transacciones globalmente.

## 1. Qué es

**Analogía:** un libro contable único repartido entre muchas oficinas que, gracias a relojes atómicos sincronizados, nunca discrepan en el orden de los asientos.

```
 Instancia "modalima-global" (configuración multirregional, 1000 PU)
   └── Base "tienda"
        ├── Tabla Inventario (PK: Sku)      ── divisiones (splits) repartidas en servidores
        ├── Tabla Pedidos (PK: PedidoId UUID)
        └── Tabla Lineas  INTERLEAVE IN PARENT Pedidos  (localidad padre-hijo)
 Réplicas lectura-escritura en 2 regiones + testigo ─ Paxos por división
```

## 2. Cómo funciona por dentro

| Pieza | Qué es |
|---|---|
| **Instancia** | Capacidad (nodos o unidades de procesamiento) y configuración regional/multirregional |
| **Edición** | Standard, Enterprise, Enterprise Plus *(verifica)* |
| **Divisiones (splits)** | Rangos de clave repartidos y replicados con Paxos |
| **TrueTime** | Reloj con incertidumbre acotada: consistencia externa |
| **Transacciones RW** | Bloqueos y reintentos automáticos por aborto |
| **Lecturas fuertes / obsoletas** | Fuertes por defecto; *stale* acotadas para menos latencia |
| **Interleaving** | Hijos guardados junto al padre |
| **Change streams** | Flujo de cambios para eventos |
| **Autoscaling** | Gestionado por el servicio *(verifica)* |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Inventario global sin sobreventa, alta escala | Spanner |
| Relacional con escala que supera una instancia | Spanner |
| Microservicio relacional modesto | [Cloud SQL](../cloud-sql/README.md) (más barato) |
| Series de tiempo, escrituras masivas sin transacciones | [Bigtable](../bigtable/README.md) |
| Documentos con app móvil | [Firestore](../firestore/README.md) |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **PU / nodo** | 1 nodo = 1000 unidades de procesamiento |
| **Hotspot** | Muchas escrituras a la misma división (claves crecientes) |
| **Clave primaria** | Define dónde vive la fila: elige UUID o claves con prefijo |
| **Mutación** | Escritura en lote dentro de una transacción |
| **Lectura obsoleta** | Datos de hace N segundos, más rápida |

## 5. Cómo se usa
1. Instancia, base con DDL y acceso: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Validación de claves y reserva de stock transaccional en [Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/spanner.sh`](ejemplos/cli/spanner.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `roles/spanner.admin` | — |
| App | — | `roles/spanner.databaseUser` en la base |
| Reportes | — | `roles/spanner.databaseReader` |

- Control fino por tabla/columna con *fine-grained access control* *(verifica)*.
- CMEK opcional; acceso privado a las APIs de Google.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Claves UUIDv4 o con prefijo de hash | Timestamps o secuencias como primera parte de la PK |
| Transacciones cortas | Llamadas HTTP dentro de una transacción RW |
| Lecturas obsoletas para catálogos | Lecturas fuertes para todo |
| Interleaving padre-hijo | Joins remotos por diseño |
| Esquema como código | Cambios DDL manuales |

## 8. Límites, costos y versiones
- **Costo:** por PU-hora según configuración y edición, más almacenamiento y respaldos *(verifica)*. Hay instancias pequeñas desde 100 PU.
- **Límites** (verifica): tamaño de transacción (mutaciones), tablas por base, PU mínimos.
- **Terraform:** `google_spanner_instance`, `google_spanner_database`.
- **Java:** `google-cloud-spanner` (cliente, JDBC y Spring Data Spanner).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
