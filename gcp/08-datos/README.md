# Google Cloud · 08 Datos

¿Dónde guardo los datos de mis microservicios según su forma, su escala y cómo los leo?

| Unidad | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Cloud SQL](cloud-sql/README.md) | ¿Dónde pongo mi base relacional de siempre? | Departamento con conserjería | Pedidos, pagos, usuarios |
| [Spanner](spanner/README.md) | ¿Y si necesito relacional a escala global sin perder consistencia? | Libro contable con relojes atómicos | Inventario global |
| [Firestore](firestore/README.md) | ¿Documentos flexibles con apps móviles? | Archivador de fichas | Carritos, perfiles |
| [Bigtable](bigtable/README.md) | ¿Millones de escrituras por segundo por clave? | Rollo ordenado por etiqueta | Telemetría, series de tiempo |
| [Memorystore](memorystore/README.md) | ¿Cómo respondo en milisegundos sin golpear la base? | Barra del café | Caché, sesiones, límites de tasa |

## Árbol de decisión: «quiero…»

```
¿Relacional con SQL y transacciones?
   ├─ ¿Cabe en una instancia (escala vertical + réplicas)?  → Cloud SQL
   └─ ¿Escala horizontal o multirregión con consistencia?    → Spanner
¿Documentos, jerarquías y clientes móviles/web?              → Firestore
¿Volumen enorme, acceso por clave/rango, sin joins?          → Bigtable
¿Lectura rápida de algo que ya está en otra base?            → Memorystore (cache-aside)
```

## Comparativa

| Característica | Cloud SQL | Spanner | Firestore | Bigtable | Memorystore |
|---|---|---|---|---|---|
| **Modelo** | Relacional | Relacional distribuido | Documentos | Columnas anchas | Clave-valor en memoria |
| **Transacciones** | ACID | ACID global | ACID (límites) | Por fila | Por comando/script |
| **Escala** | Vertical + réplicas | Horizontal | Automática | Por nodos | Por nodos/shards |
| **Cobro** | Instancia | PU | Operaciones | Nodos + GB | Capacidad |
| **Acceso Java** | JDBC + conector | Cliente/JDBC | Cliente | Cliente/HBase | Lettuce |
| **Error típico** | Pool × instancias | PK creciente | Documento caliente | Fecha al inicio | Sin TTL |

## La receta ModaLima
| Necesidad | Pieza | Por qué |
|---|---|---|
| Pedidos y pagos | Cloud SQL PostgreSQL con HA, IAM auth y PITR | Relacional estándar |
| Stock de preventas globales | Spanner con transacción RW | Sin sobreventa |
| Carritos y preferencias | Firestore con TTL | Flexible y móvil |
| Telemetría de máquinas de Café Andino | Bigtable `maquina#tsInvertido` | Escrituras masivas |
| Catálogo caliente | Memorystore con jitter | Milisegundos |

## Orden recomendado de adopción
1. Cloud SQL con conector, IAM y pools calculados.
2. Memorystore delante de lo más leído.
3. Firestore para datos de apps.
4. Bigtable cuando el volumen lo pida.
5. Spanner solo cuando la escala o la geografía lo justifiquen.

## Reglas transversales
- Sin IP pública ni contraseñas: red privada e IAM.
- La clave define el rendimiento: evita claves crecientes.
- Esquema, índices y retención como código.
- Respaldos/PITR probados.
- Un cliente por aplicación, nunca por petición.

## Java en datos: qué construye cada `uso-en-java.md`
| Unidad | Qué construyes | Patrón común |
|---|---|---|
| Cloud SQL | Propiedades del conector con IAM y pool | Configuración pura |
| Spanner | Revisión de PK y reserva transaccional | Bloque reintentable |
| Firestore | Contador distribuido | `ApiFuture` esperado |
| Bigtable | Clave con timestamp invertido | Lectura por prefijo |
| Memorystore | Cache-aside con token IAM | Degradar si falla |

## Cómo se relaciona con otros capítulos
- [Red](../01-red/README.md): PSA y PSC.
- [IAM](../02-iam/README.md): autenticación IAM en bases.
- [Secretos](../03-secretos/README.md): CMEK.
- [Mensajería](../07-mensajeria/README.md): eventos hacia y desde los datos.
- [Gobierno](../09-gobierno/README.md): políticas como `sql.restrictPublicIp`.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos, troubleshooting, repaso y prompt de NotebookLM.
