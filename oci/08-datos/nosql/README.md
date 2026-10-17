# Oracle OCI · Datos · NoSQL Database Cloud Service

Base de datos clave-valor y de documentos JSON, sin servidores, con latencia predecible de milisegundos a cualquier escala. Defines tablas con una **clave primaria** (y una **clave de *shard*** dentro de ella), eliges capacidad (unidades de lectura/escritura o bajo demanda) y operas filas por clave o con consultas SQL sencillas.

## 1. Qué es

**Analogía:** una pared de casilleros numerados. Si sabes el número (la clave), abres el casillero al instante, sin importar cuántos haya. Si buscas «todos los casilleros con abrigos rojos», tienes que recorrer muchos (consulta), y eso cuesta más.

```
 Tabla "carritos"   PRIMARY KEY (SHARD(id_cliente), id_carrito)   TTL 7 DAYS
   ├─ fila: {id_cliente:"C-9", id_carrito:"actual", items:[…], total:189.90}   versión v3
   └─ capacidad: lecturas/escrituras por segundo + GB (o bajo demanda)
 App ── get/put por clave (ms) ── query SQL (más costosa) ── índices secundarios
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Tabla** | Esquema fijo, JSON o mixto; clave primaria obligatoria |
| **Clave de shard** | Parte de la clave que decide la partición física: filas con la misma clave de shard viven juntas |
| **Capacidad** | *Provisioned* (unidades de lectura, escritura y GB) u *on demand* |
| **TTL** | Tiempo de vida por tabla o por fila: expiran solas |
| **Versión** | Cada fila tiene versión: escrituras condicionales (`IfPresent`, `IfAbsent`, `ifMatch`) |
| **Consistencia** | `EVENTUAL` (más barata) o `ABSOLUTE` en lecturas |
| **Índices** | Secundarios sobre campos (también dentro de JSON) |
| **Réplicas globales** | Tablas activo-activo entre regiones *(verifica)* |

### Costo de una operación
- Leer o escribir una fila consume unidades según su tamaño (1 KB por unidad, aprox. *(verifica)*).
- Una consulta sin clave recorre muchas filas y consume muchas unidades.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Carrito, sesión, preferencias, perfil por id | **NoSQL** |
| Catálogo de lectura masiva por SKU | **NoSQL** |
| Eventos de dispositivo por id y tiempo | **NoSQL** (clave de shard = dispositivo) |
| Transacciones entre muchas entidades, *joins* y reportes | **No**: base relacional |
| Búsqueda de texto completo | **No**: un motor de búsqueda |
| Datos que caben en una tabla relacional pequeña | Probablemente relacional |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Diseño por patrón de acceso** | Primero las preguntas, después la tabla |
| **Clave de shard** | Agrupa filas que se leen juntas; no la satures |
| **Fila caliente** | Una clave que recibe casi todo el tráfico |
| **Concurrencia optimista** | Escribe solo si la versión no cambió |
| **TTL** | Borrado automático por edad |

## 5. Cómo se usa
1. Tabla con TTL y capacidad: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Guarda el carrito con control de versión para no pisar cambios concurrentes: [uso en Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/nosql.sh`](ejemplos/cli/nosql.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `manage nosql-tables` | — |
| App | — | `use nosql-rows` (leer/escribir filas) en su tabla |
| Lectores | — | `read nosql-rows` |

- Acceso por IAM (sin usuarios de base de datos): políticas por tabla (`target.nosql-table.name`).
- Desde subredes privadas, por la puerta de servicios.
- No guardes datos personales que no necesites; usa TTL para lo temporal.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Diseñar la clave por cómo vas a leer | Copiar el modelo relacional |
| Escrituras condicionales por versión | La última escritura gana siempre |
| TTL para sesiones y carritos | Jobs que borran filas viejas |
| Consistencia eventual donde se pueda | `ABSOLUTE` en todo |
| Medir unidades consumidas | Consultas sin clave en cada petición |

## 8. Límites, costos y versiones
- **Costo:** por unidades de lectura/escritura y GB (o por uso bajo demanda); nivel siempre gratis con límites *(verifica)*.
- **Límites** (verifica): tamaño de fila, tablas por tenancy, unidades máximas por tabla.
- **Terraform:** `oci_nosql_table`, `oci_nosql_index`.
- **SDK:** `NosqlClient` (`oci-java-sdk-nosql`); también existe el driver específico de Oracle NoSQL.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
