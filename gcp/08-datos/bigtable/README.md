# Google Cloud · Datos · Bigtable

Base **NoSQL de columnas anchas** para volúmenes enormes con baja latencia: filas ordenadas por **clave de fila**, agrupadas en **familias de columnas**, con versiones por celda. Escala sumando nodos (o con autoescalado) y es compatible con la API de HBase. Ideal para series de tiempo, telemetría, perfiles de usuario a gran escala y *feature stores*.

## 1. Qué es

**Analogía:** un rollo de papel continuo ordenado alfabéticamente por la etiqueta de cada renglón. Encontrar un renglón o leer un tramo seguido es instantáneo; buscar por algo que no sea la etiqueta obliga a leer todo el rollo.

```
 Instancia "telemetria-cafe" ─ clúster A (southamerica-east1-a, 3 nodos) ⇄ replicación ⇄ clúster B (otra zona)
   └── Tabla "lecturas"  familia "m" (GC: 30 días)
        fila: maquina-017#9223370300000000000   m:temp=92.1  m:presion=9.0
        fila: maquina-017#9223370300000005000   ...
 Perfiles de app: enrutado a un clúster (escrituras) o multi-clúster (lecturas)
```

## 2. Cómo funciona por dentro

| Pieza | Qué es |
|---|---|
| **Instancia / clústeres** | Uno o varios clústeres con replicación entre zonas o regiones |
| **Nodos** | Capacidad de cómputo; el almacenamiento está separado (SSD o HDD) |
| **Tabla** | Filas ordenadas lexicográficamente por clave |
| **Familia de columnas** | Agrupa columnas y define la recolección de basura (versiones/edad) |
| **Tablets** | Rangos de filas que se reparten y rebalancean solos |
| **Perfil de aplicación** | Política de enrutado y transacciones de una sola fila |
| **Escrituras** | Atómicas por fila; sin transacciones entre filas |
| **SQL** | Consultas GoogleSQL sobre Bigtable *(verifica)* |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Telemetría de miles de máquinas de café | Bigtable |
| Historial de eventos por usuario a gran escala | Bigtable |
| Transacciones entre filas, joins | [Spanner](../spanner/README.md) o [Cloud SQL](../cloud-sql/README.md) |
| Menos de 1 TB y consultas variadas | [Firestore](../firestore/README.md) o Cloud SQL |
| Analítica ad hoc | BigQuery (consultas federadas a Bigtable) |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Clave de fila** | El único índice: diseña para tus lecturas |
| **Timestamp invertido** | `Long.MAX_VALUE - ts` para leer lo último primero |
| **Hotspot** | Claves que empiezan con fecha concentran escrituras |
| **GC policy** | Cuánto guardar por celda (versiones o edad) |
| **Perfil de app** | Cómo se enruta cada cliente |

## 5. Cómo se usa
1. Instancia, tabla, familia con GC y acceso: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Diseño de clave y escritura/lectura por rango en [Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/bigtable.sh`](ejemplos/cli/bigtable.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `roles/bigtable.admin` | — |
| App | — | `roles/bigtable.user` |
| Lectores | — | `roles/bigtable.reader` |

- IAM a nivel de instancia y tabla; CMEK opcional; acceso privado a las APIs.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Clave = entidad + tiempo (invertido si lees lo último) | Clave que empieza por fecha |
| Familias pocas con GC | Guardar versiones infinitas |
| Leer por prefijo o rango | Escaneos completos |
| Probar con Key Visualizer | Diseñar sin datos reales |
| Mínimo de nodos según CPU y almacenamiento | Instancias de producción con 1 nodo |

## 8. Límites, costos y versiones
- **Costo:** por nodo-hora, almacenamiento SSD/HDD por GB y replicación *(verifica)*.
- **Límites** (verifica): celdas ≤ 10 MB recomendado (100 MB máximo), filas ≤ 256 MB, CPU objetivo ~70 %.
- **Terraform:** `google_bigtable_instance`, `google_bigtable_table`, `google_bigtable_app_profile`.
- **Java:** `google-cloud-bigtable` (`BigtableDataClient`) o cliente HBase.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
