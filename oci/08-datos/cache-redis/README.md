# Oracle OCI · Datos · OCI Cache (compatible con Redis/Valkey)

Caché en memoria administrada, compatible con el protocolo Redis (motores Redis OSS o Valkey *(verifica versiones)*). Respuestas en microsegundos para lo que se lee mucho y cambia poco: catálogos, sesiones, contadores, límites de tasa, resultados de consultas caras.

## 1. Qué es

**Analogía:** el mostrador junto a la caja donde el barista deja los cafés más pedidos ya listos. No es la cocina (la base de datos): si un café no está en el mostrador, se prepara y se deja ahí un rato. Si el mostrador se vacía, nadie se queda sin café; solo tarda un poco más.

```
 App ──(1) GET catalogo:v3:POL-01 ──► OCI Cache (primario + réplicas, subred privada, TLS)
   │        └─ acierto: microsegundos
   └─(2) fallo → base de datos → (3) SET con TTL + jitter
 Endpoints: primario (escritura) · réplicas (lectura) · modo clúster con shards (opcional)
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Clúster** | Nodos con la misma memoria; modo no particionado (1 primario + réplicas) o **sharded** |
| **Endpoints** | FQDN del primario, de réplicas y de descubrimiento (modo clúster) |
| **Config set** | Parámetros del motor (por ejemplo política de expulsión `maxmemory-policy`) |
| **Usuarios** | ACL de Redis con contraseña o autenticación IAM *(verifica)* |
| **TLS** | Cifrado en tránsito (siempre activo) |
| **Respaldos** | Exportar/importar a Object Storage *(verifica)* |

### Comportamiento
- Datos en memoria: si se pierde un nodo, la réplica toma el lugar; **una caché no es la fuente de verdad**.
- Al llenarse, expulsa claves según la política (`allkeys-lru`, `volatile-ttl`…).
- Las réplicas pueden ir milisegundos atrás del primario.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Ficha de producto leída mil veces por segundo | **Cache** (cache-aside) |
| Sesiones HTTP compartidas entre réplicas | **Cache** |
| Límite de tasa por usuario (contador con expiración) | **Cache** |
| Bloqueo distribuido corto | **Cache** (con cuidado y expiración) |
| Única copia de datos importantes | **No**: base de datos |
| Cola de trabajo con reintentos | **No**: [Queue](../../07-mensajeria/queue/README.md) |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Cache-aside** | La app busca en caché; si no está, va a la base y guarda |
| **TTL con jitter** | Expiración con variación aleatoria para que no expire todo a la vez |
| **Estampida** | Muchas peticiones regeneran la misma clave al mismo tiempo |
| **Versión en la clave** | Cambiar `v3` por `v4` invalida todo de golpe sin borrar |
| **Expulsión** | Borrado automático cuando falta memoria |

## 5. Cómo se usa
1. Clúster con réplicas en subred privada: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Claves con espacio de nombres y versión, TTL con jitter, y descubrimiento de endpoints: [uso en Java](uso-en-java.md). El acceso a datos se hace con el cliente Redis del framework (Lettuce en Spring Data Redis, cliente Redis de Quarkus).
3. Prueba de conexión: [`ejemplos/cli/cache.sh`](ejemplos/cli/cache.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `manage redis-family` | — |
| App (descubrir endpoints) | `read redis-clusters` | Usuario ACL de Redis (contraseña en Vault) |

- Subred privada; NSG 6379 solo desde las apps.
- TLS siempre; usuario con permisos acotados a sus prefijos de clave.
- No guardes datos personales completos; si lo haces, TTL corto.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Claves `servicio:version:id` | Claves sin espacio de nombres |
| TTL siempre, con jitter | Claves sin expiración |
| Protección contra estampida (un solo regenerador) | Que mil peticiones consulten la base a la vez |
| Tolerar la caída de la caché | Que la app caiga si la caché no responde |
| `SCAN` para recorrer | `KEYS *` en producción |

## 8. Límites, costos y versiones
- **Costo:** por GB de memoria por nodo y hora *(verifica)*.
- **Límites** (verifica): nodos por clúster, memoria por nodo, shards, versiones del motor.
- **Terraform:** `oci_redis_redis_cluster`, `oci_redis_oci_cache_user`.
- **SDK:** `RedisClusterClient` (`oci-java-sdk-redis`) para gestión; datos con Lettuce/cliente Redis.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
