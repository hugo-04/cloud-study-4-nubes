# Google Cloud · Datos · Memorystore

**Caché en memoria administrada**: Memorystore for **Valkey** (el sucesor abierto de Redis, recomendado para lo nuevo), for **Redis Cluster**, for **Redis** (instancias básicas/estándar) y for **Memcached** *(verifica la oferta vigente)*. Google opera nodos, réplicas, conmutación y parches; tú eliges tamaño y configuraciones. Tu código usa los clientes de siempre (Lettuce/Spring Data Redis, Quarkus Redis).

## 1. Qué es

**Analogía:** la barra de un café: lo más pedido ya está preparado a mano del barista; si no está, se va a la cocina (base de datos) y se deja una porción lista para el siguiente.

```
 Cloud Run / GKE ── (VPC: PSC o acceso privado) ──▶ Memorystore for Valkey "cache-tienda"
                                                    ├─ shard 1: primario zona a + réplica zona b
                                                    ├─ shard 2: …
                                                    └─ TLS en tránsito · autenticación IAM
   cache-aside: GET producto:123 → miss → Cloud SQL → SET producto:123 EX 600±60
```

## 2. Cómo funciona por dentro

| Pieza | Qué es |
|---|---|
| **Instancia / clúster** | Nodos con memoria; modo clúster reparte claves en shards |
| **Réplicas** | En otras zonas; conmutación automática |
| **Conectividad** | Solo privada: PSC (clúster/Valkey) o acceso privado a servicios (Redis clásico) |
| **Autenticación** | IAM (clúster/Valkey) o cadena AUTH (Redis clásico) |
| **TLS en tránsito** | Opcional; actívalo |
| **Persistencia** | RDB/AOF opcional *(verifica)* |
| **Política de expulsión** | `maxmemory-policy` (p. ej. `allkeys-lru`) |
| **Mantenimiento** | Ventana definida |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Caché de catálogo y sesiones | Memorystore |
| Limitar tasa, contadores efímeros, colas livianas | Memorystore |
| Fuente de verdad de pedidos | [Cloud SQL](../cloud-sql/README.md) o [Spanner](../spanner/README.md) |
| Documentos persistentes con app móvil | [Firestore](../firestore/README.md) |
| Datos masivos en disco | [Bigtable](../bigtable/README.md) |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Cache-aside** | La app busca en caché y, si falta, carga y guarda |
| **TTL con *jitter*** | Caducidad con variación para evitar estampidas |
| **Estampida** | Muchas claves vencen a la vez y golpean la base |
| **Modo clúster** | Claves repartidas; comandos multi-clave con *hash tags* |
| **Expulsión** | Qué se borra cuando se llena |

## 5. Cómo se usa
1. Instancia Valkey con PSC y alta disponibilidad: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Cache-aside con TTL y *jitter* en [Java](uso-en-java.md) con Lettuce.
3. CLI: [`ejemplos/cli/memorystore.sh`](ejemplos/cli/memorystore.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `roles/memorystore.admin` (o `redis.admin`) | — |
| App | — | `roles/memorystore.dbConnectionUser` con IAM auth *(verifica)*, o la cadena AUTH desde Secret Manager |

- Solo red privada; TLS en tránsito; la cadena AUTH nunca en el repositorio.
- No guardes datos personales sin necesidad: es caché.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| TTL siempre, con *jitter* | Claves sin caducidad |
| Tolerar que la caché falle (degradar a la base) | Que la app caiga si la caché cae |
| Alta disponibilidad con réplicas | Instancia básica en producción |
| `KEYS *` prohibido; usa `SCAN` | Comandos O(n) en producción |
| Prefijos por dominio (`producto:`) | Claves sin convención |

## 8. Límites, costos y versiones
- **Costo:** por GB-hora de capacidad (o por nodo) y réplicas *(verifica)*.
- **Límites** (verifica): tamaños de nodo, shards por clúster, conexiones por nodo.
- **Versiones:** Valkey 7.2/8.x, Redis 7.x *(verifica)*.
- **Terraform:** `google_memorystore_instance` (Valkey), `google_redis_cluster`, `google_redis_instance`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
