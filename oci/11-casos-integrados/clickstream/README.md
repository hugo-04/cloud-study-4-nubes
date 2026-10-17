# Oracle OCI · Caso integrado · Clickstream de ModaLima

Medir en casi tiempo real qué productos se ven y agregan al carrito, para el tablero de *merchandising* y las recomendaciones, y guardar todo para análisis histórico. Miles de eventos por segundo en el Cyber, orden por sesión, relectura si un consumidor falla.

## 1. Qué es

**Analogía:** el conteo de personas en los pasillos de un centro comercial. Sensores en cada pasillo (navegadores) envían cada paso a una central (stream); un equipo cuenta por minuto y pasillo (ventanas); otro guarda las grabaciones en el archivo (Object Storage) por si hay que recontar.

```
 Navegador ─► API Gateway (límite de tasa) ─► "colector" (pods, productor por lotes)
                                                │ clave = idSesion
                                                ▼
                               Streaming "clickstream" (6–12 particiones, 72 h)
            ┌───────────────────────┬─────────────────────────────┐
            ▼                       ▼                             ▼
 grupo "tablero"            grupo "recomendaciones"       Service Connector
 ventanas de 1 min          (consumidor propio)           ─► Object Storage (historial, Parquet/JSON)
 ─► OCI Cache (top SKUs)
```

## 2. Cómo funciona por dentro

### El viaje de un clic
1. El navegador envía lotes de eventos (`vista`, `carrito`) con `idSesion`, `sku`, `ts` (hora del evento).
2. El colector valida, recorta campos y publica por lotes con clave `idSesion` (orden por sesión) — ver [Streaming](../../07-mensajeria/streaming/README.md).
3. El grupo `tablero` lee, agrega por **ventanas de 1 minuto según la hora del evento** y escribe el top en la caché.
4. Una **marca de agua** decide cuándo cerrar una ventana: hora del evento más reciente − retraso permitido (por ejemplo 30 s).
5. Service Connector copia todo a Object Storage para análisis histórico y reprocesos.

### Garantías y decisiones
| Tema | Decisión |
|---|---|
| Orden | Solo por sesión (misma clave → misma partición) |
| Duplicados | Al menos una vez: el tablero tolera pequeñas desviaciones; para conteos exactos, deduplica por `idEvento` |
| Eventos tardíos | Se aceptan dentro del retraso permitido; los más tardíos van a un contador aparte |
| Relectura | Desde el último commit del grupo o una hora (`AT_TIME`) |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Métricas de producto casi en tiempo real | **Este caso** |
| Analítica histórica de meses | Object Storage + motor de consultas / ADW |
| Facturación exacta | **No** con agregados aproximados: usa la base transaccional |
| Pocos eventos por minuto | Una tabla y una consulta pueden bastar |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Hora del evento vs hora de proceso** | Cuándo pasó vs cuándo lo vimos |
| **Ventana fija (*tumbling*)** | Bloques de 1 minuto sin solaparse |
| **Marca de agua** | «Ya no espero eventos anteriores a X» |
| **Commit del grupo** | Hasta dónde se procesó |
| **Seudonimización** | Reemplazar identificadores personales por códigos |

## 5. Cómo se usa
1. Stream, pool privado y conector a Object Storage: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Agregador por ventanas con marca de agua y lector de grupo en Java: [uso en Java](uso-en-java.md).
3. Generar tráfico de prueba: [`ejemplos/cli/clicks.sh`](ejemplos/cli/clicks.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Colector | — | `use stream-push` |
| Consumidores | — | `use stream-pull` |
| Service Connector | Política de servicio | Lee el stream, escribe en el bucket |

- Sin datos personales en claro: `idSesion` aleatorio, sin correo ni IP completa.
- Límite de tasa en el gateway para evitar inundaciones.
- Bucket histórico privado y con ciclo de vida.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Agregar por hora del evento | Contar por hora de llegada |
| Marca de agua con retraso permitido | Cerrar ventanas al instante |
| Commit después de escribir el agregado | Commit al leer |
| Historial en Object Storage | Depender de la retención del stream |
| Clave por sesión | Clave por SKU popular (partición caliente) |

## 8. Límites, costos y versiones
- **Costo:** particiones-hora + GB escritos + retención; Service Connector y Object Storage *(verifica)*.
- **Límites** (verifica): MB/s por partición, tamaño de mensaje, retención máxima.
- **Terraform:** `oci_streaming_stream_pool`, `oci_streaming_stream`, `oci_sch_service_connector`.
- **SDK:** `StreamClient` (`createGroupCursor`, `getMessages`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
