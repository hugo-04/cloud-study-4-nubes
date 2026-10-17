# Transversal · Apache Kafka

**Log distribuido de eventos**: los productores agregan registros al final de **temas** divididos en **particiones**; los consumidores los leen a su ritmo, en orden dentro de cada partición, y pueden **releer** moviendo su posición (*offset*). Los datos se retienen por tiempo o tamaño (o se **compactan** por clave), así que Kafka sirve a la vez de mensajería, almacenamiento de eventos y base para procesamiento en flujo. Cómo se ofrece administrado en cada nube está en el capítulo de mensajería de esa nube.

## 1. Qué es

**Analogía:** un libro de actas por capítulos. Cada capítulo (partición) solo crece al final y sus páginas están numeradas (offsets). Varios equipos leen el mismo libro, cada uno con su marcapáginas (grupo de consumidores); nadie arranca páginas al leer.

```
 Productores ──(clave = idPedido)──► tema "pedidos"
                                      ├─ partición 0: [0][1][2][3][4]…   líder: broker 1, réplicas 2,3
                                      ├─ partición 1: [0][1][2]…         líder: broker 2
                                      └─ partición 2: [0][1][2][3]…      líder: broker 3
 grupo "facturacion": consumidor A ← p0, p1 · consumidor B ← p2    (offsets confirmados por partición)
 grupo "analitica":   consumidor X ← p0, p1, p2                    (lee lo mismo, a su ritmo)
```

## 2. Cómo funciona por dentro

| Pieza | Qué es |
|---|---|
| **Broker** | Servidor que guarda particiones; el clúster se coordina con **KRaft** (sin ZooKeeper desde Kafka 4) |
| **Tema / partición** | Unidad lógica / unidad de orden, paralelismo y réplica |
| **Réplicas e ISR** | Copias de cada partición; ISR = réplicas al día con el líder |
| **Offset** | Posición de un registro en su partición |
| **Productor** | Agrupa en lotes por partición (`batch.size`, `linger.ms`), comprime y envía; la clave decide la partición |
| **`acks`** | `0` (sin confirmación), `1` (líder), `all` (todas las ISR; con `min.insync.replicas`) |
| **Idempotencia** | `enable.idempotence=true`: sin duplicados por reintentos del productor |
| **Grupo de consumidores** | Reparte particiones entre miembros; un miembro por partición |
| **Rebalanceo** | Redistribución al entrar/salir miembros; el cooperativo evita parar todo |
| **Commit de offsets** | Automático (riesgo de perder) o manual tras procesar |
| **Transacciones** | Escritura atómica en varias particiones + offsets: *exactly-once* dentro de Kafka |
| **Compactación** | Conserva el último valor por clave (tablas de estado, configuración) |
| **Schema Registry** | Esquemas versionados (Avro, Protobuf, JSON Schema) con reglas de compatibilidad |
| **Kafka Connect / Streams** | Integración con sistemas externos / procesamiento en flujo con estado |

### Garantías de entrega
| Modo | Cómo | Riesgo |
|---|---|---|
| Como mucho una vez | Commit antes de procesar | Pérdida |
| **Al menos una vez** (lo habitual) | Procesar y luego commit | Duplicados → consumidor idempotente |
| Exactamente una vez | Transacciones lectura-proceso-escritura dentro de Kafka | Solo dentro de Kafka; hacia una base externa sigue haciendo falta idempotencia |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Eventos de dominio que consumen varios equipos | Kafka |
| Orden por entidad y relectura (reprocesar, nuevos consumidores) | Kafka |
| Flujo de alto volumen (clics, telemetría, logs) | Kafka |
| Pocas tareas con reintentos por mensaje y retrasos programados | Una cola de trabajos es más simple |
| Pedir/responder síncrono | HTTP/gRPC, no Kafka |
| Un único consumidor y bajo volumen | Una cola simple o la propia base |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Clave** | Decide la partición: mismo valor ⇒ mismo orden |
| **Lag** | Mensajes pendientes de un grupo |
| **DLT (dead letter topic)** | Tema donde van los mensajes que no se pudieron procesar |
| **Retención** | Cuánto tiempo/tamaño se guardan los datos |
| **Compatibilidad de esquema** | `BACKWARD`: consumidores nuevos leen datos viejos |
| **Partición caliente** | Una clave muy frecuente concentra el tráfico |

## 5. Cómo se usa
- Configuraciones seguras de productor y consumidor, consumidor idempotente y DLT con Spring Kafka, Reactor Kafka y Quarkus Messaging: [uso en Java](uso-en-java.md).
- Dimensionar particiones: `particiones ≥ throughput_objetivo / throughput_por_consumidor`, con margen; aumentar particiones después **cambia el mapeo de claves**.
- Nombres de temas: `<dominio>.<entidad>.<evento>.v<N>` (p. ej. `ventas.pedido.pagado.v1`).

## 6. Seguridad
| Capa | Control |
|---|---|
| Transporte | TLS siempre |
| Autenticación | SASL (SCRAM, OAUTHBEARER) o mTLS; identidades por aplicación |
| Autorización | ACL por tema y grupo (`READ`, `WRITE`, `DESCRIBE`) con mínimo privilegio |
| Datos | Sin datos sensibles en claro; cifrado a nivel de campo si hace falta |
| Esquemas | Registro con permisos de escritura limitados |

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| `acks=all`, idempotencia, `min.insync.replicas=2` con réplica 3 | `acks=1` en datos de negocio |
| Commit manual tras procesar | Auto-commit con procesamiento asíncrono |
| Consumidor idempotente (id de evento) | Suponer entrega única |
| Clave por entidad | Clave aleatoria cuando importa el orden |
| DLT + alerta | Reintentar sin fin bloqueando la partición |
| Esquemas versionados con compatibilidad | JSON libre que cambia sin aviso |
| Temas como código | Auto-creación de temas en producción |

## 8. Casos reales
| Historia | Qué pasó | Lección |
|---|---|---|
| El mensaje venenoso | Un evento mal formado de ModaLima detuvo la partición 3 horas (reintento infinito) | Reintentos acotados + DLT |
| Pagos repetidos | Un rebalanceo en Café Andino reentregó un lote ya procesado sin commit | Idempotencia por id de evento |
| El orden roto | Al pasar de 6 a 12 particiones, eventos de un mismo pedido cayeron en particiones distintas durante la transición | Planificar particiones desde el inicio |
| El esquema incompatible | Se renombró un campo y los consumidores antiguos fallaron | Compatibilidad `BACKWARD` en el registro |
| Rebalanceos en bucle | Procesar cada lote tomaba más que `max.poll.interval.ms` | Lotes más chicos o subir el intervalo |

**Versiones:** Kafka 4.x (KRaft), `kafka-clients` 4.x, Spring for Apache Kafka 4.x, Quarkus Messaging Kafka 3.40 *(verifica)*.

**Siguiente:** [uso en Java](uso-en-java.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md) · [índice transversal](../README.md)
