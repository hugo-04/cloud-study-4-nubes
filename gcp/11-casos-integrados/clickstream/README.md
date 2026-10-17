# Google Cloud · Caso integrado · Clickstream de ModaLima

Medir en casi tiempo real qué productos se ven y agregan al carrito, para el tablero de *merchandising*, y guardar todo para análisis histórico. Miles de eventos por segundo en el Cyber, orden por sesión y relectura si un consumidor falla.

## 1. Qué es

**Analogía:** el conteo de personas en los pasillos de un centro comercial: sensores (navegadores) envían cada paso a una central (Kafka); un equipo cuenta por minuto y pasillo (ventanas); otro guarda las grabaciones en el archivo (BigQuery) por si hay que recontar.

```
 Navegador ─► LB + Cloud Armor (límite de tasa) ─► Cloud Run "colector" (productor por lotes, acks=all)
                                                    │ clave = idSesion
                                                    ▼
                       Managed Kafka "eventos-modalima" · tema clickstream (12 particiones, 7 días)
            ┌─────────────────────────┬──────────────────────────────┐
            ▼                         ▼                              ▼
 grupo "tablero" (GKE)       grupo "recomendaciones"        Kafka Connect administrado
 ventanas de 1 min           (consumidor propio)            ─► BigQuery (historial, particionado por día)
 ─► Memorystore (top SKUs)
```

## 2. Cómo funciona por dentro

### El viaje de un clic
1. El navegador envía lotes de eventos (`vista`, `carrito`) con `idSesion`, `sku` y `ts` (hora del evento).
2. El colector valida, recorta campos y produce por lotes con clave `idSesion` (orden por sesión) — ver [Managed Kafka](../../07-mensajeria/managed-kafka/README.md).
3. El grupo `tablero` lee sin commit automático, agrega por **ventanas de 1 minuto según la hora del evento** y escribe el top en [Memorystore](../../08-datos/memorystore/README.md).
4. Una **marca de agua** (máximo visto − 30 s) decide cuándo cerrar una ventana; lo que llega tarde se cuenta aparte.
5. Kafka Connect copia todo a BigQuery para análisis y reprocesos *(verifica conectores disponibles)*.

### Garantías y decisiones
| Decisión | Por qué |
|---|---|
| Clave = sesión | Orden de la navegación de cada persona |
| Hora del evento, no de llegada | Los móviles envían con retraso |
| Commit después de escribir | Si el pod cae, se relee (al menos una vez) |
| Escritura idempotente en la caché | Reemplazar el top de la ventana, no sumar |
| 12 particiones | Paralelismo máximo del grupo `tablero` |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Eventos de alto volumen con orden por clave y relectura | Este diseño |
| Pocos eventos de negocio entre servicios | Pub/Sub |
| Analítica sin tiempo real | Carga directa a BigQuery |
| Exactitud contable | No: esto es aproximado y tolera duplicados |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Ventana fija** | Agrupar por minuto exacto |
| **Marca de agua** | Hasta dónde creo haber visto todo |
| **Tardío** | Evento de una ventana ya cerrada |
| **Lag** | Cuánto falta por leer del grupo |
| **Commit manual** | Confirmar el avance solo tras escribir |

## 5. Cómo se usa
1. Tema, cuentas y permisos: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Agregador con marca de agua y lector con commit manual en [Java](uso-en-java.md).
3. Diagnóstico: [`ejemplos/cli/clicks.sh`](ejemplos/cli/clicks.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| `run-colector` | — | `roles/managedkafka.client` (producir) |
| `gke-tablero` (Workload Identity) | — | `roles/managedkafka.client` + acceso a Memorystore |
| Analistas | — | `roles/bigquery.dataViewer` en el dataset |

- Sin datos personales: `idSesion` seudónimo, sin IP completa.
- Límite de tasa en el borde contra inundaciones.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Agrupar por hora del evento | Usar la hora de llegada |
| Commit tras escribir | `enable.auto.commit=true` |
| Escribir el top idempotente | Incrementar contadores en la caché por mensaje |
| Alertar por lag | Enterarse por el tablero vacío |
| Retención suficiente para reprocesar | Retención mínima |

## 8. Límites, costos y versiones
- **Costo:** clúster de Managed Kafka (vCPU/memoria), almacenamiento, BigQuery y Memorystore *(verifica)*.
- **Límites** (verifica): particiones por clúster, tamaño de mensaje, throughput por vCPU.
- **Java:** `kafka-clients` con OAUTHBEARER (ver la unidad de Managed Kafka).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
