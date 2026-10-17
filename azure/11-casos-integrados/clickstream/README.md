# Azure · Caso integrado · Clickstream con Event Hubs

ModaLima quiere saber **qué hace la gente en su web y su app en tiempo real**: qué páginas se visitan por minuto, cuántas sesiones únicas hay y qué pasa durante una campaña. Son miles de eventos pequeños por segundo, con picos. Este caso muestra cómo dimensionar, repartir y analizar ese flujo con Event Hubs, y dónde está la frontera entre «en vivo y aproximado» y «exacto pero después».

## 1. Qué es

**Analogía:** el conteo de gente en la entrada de un estadio. Los torniquetes (colector) anotan cada entrada sin discutir; una cinta transportadora con varios carriles (particiones) lleva las anotaciones; al final de la cinta, un equipo hace el conteo rápido para el marcador (agregador en línea), mientras otro lo archiva todo en cajas (Capture → lago) para el informe oficial de mañana.

```
 Web/App ──lote≤100──► Colector (valida, seudonimiza) ──► Event Hubs «clics» ── 8 particiones ──┬─► grupo «agregador» ─► Redis/tabla (por minuto)
                                                                                                 ├─► CAPTURE ─► Data Lake (Avro, crudo)
                                                                                                 └─► grupo «reproceso» ─► recálculo exacto
 Clave de partición = cubeta de la sesión (el orden de cada sesión se conserva)
```

## 2. Cómo funciona por dentro

| Pieza | Qué hace | Detalle que importa |
|---|---|---|
| **Colector** | Recibe lotes por HTTP (202), valida y seudonimiza | Rechaza fechas imposibles; nunca publica el identificador real de sesión |
| **Event Hubs** | Registro ordenado por partición, con retención | **Una partición = un orden.** La clave decide la partición |
| **Cubetas** | `hash(sesión) mod 64` como clave de partición | Un lote del SDK admite una sola clave: con cubetas hay ≤64 lotes por solicitud y cada sesión mantiene su orden |
| **Grupo «agregador»** | Un lector independiente con sus puntos de control | Cada grupo tiene los suyos; no se pisan |
| **Ventanas por minuto** | Cuenta visitas y sesiones únicas por página | Tolerancia a eventos tardíos (2 min) y descarte de repetidos |
| **Capture** | Vuelca el flujo a Data Lake en Avro cada 5 min | Fuente de verdad para recalcular; no necesita código |
| **Resumen** | Se guarda con UPSERT por (ventana, página) | Idempotente: reintentos y reprocesos no suman dos veces |

### Dimensionar con números (ejemplo ModaLima)

| Dato | Valor |
|---|---|
| Pico esperado | 5 000 clics/s (Black Friday) |
| Tamaño medio | 400 B |
| Margen de crecimiento | ×1,5 |
| Lectores independientes | 3 (agregador, reproceso, Capture) |
| Consumidores en paralelo | 6 instancias |

Resultado del [planificador](uso-en-java.md): **~2,9 MB/s de entrada**, **~8,6 MB/s de salida**, **8 unidades** (manda el límite de eventos por segundo: 7 500 / 1 000) y **8 particiones** (≥ consumidores en paralelo y ≥ unidades). Reglas por unidad del nivel Standard (verifica en la doc oficial): ≈1 MB/s o 1 000 eventos/s de entrada y 2 MB/s de salida. **Auto-inflate** deja crecer hasta un tope para cuidar el costo.

### Clave caliente (*hot key*)
Si la clave fuera la **página**, la portada concentraría el 40 % del tráfico en una sola partición mientras las demás duermen. Con la **sesión** (o su cubeta) el reparto es parejo. Un bot que dispara 200 000 eventos con la misma sesión sigue siendo caliente: el [detector de sesgo](uso-en-java.md) lo señala y el colector puede limitar por sesión.

## 3. Para qué sirve y cuándo NO

| Situación | ¿Event Hubs? | Alternativa |
|---|---|---|
| Miles de eventos/s de clics, métricas, IoT | ✅ | — |
| Varios lectores independientes del mismo flujo | ✅ | — |
| Reproducir el pasado (reprocesar) | ✅ dentro de la retención; más allá, el lago | — |
| 50 eventos por minuto | ⚠️ Excesivo | Service Bus o una tabla |
| Cada mensaje es una orden que no puede perderse ni repetirse | ❌ | Service Bus (ver tienda online) |
| Cálculos exactos con ventanas complejas y estado grande | ⚠️ El agregador es ligero | Un motor de procesamiento de flujos (verifica opciones de Azure) |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Partición** | Un carril ordenado del flujo; el paralelismo máximo de lectura es el número de particiones |
| **Clave de partición** | Lo que decide el carril; mismo valor, mismo carril |
| **Unidad de rendimiento (TU)** | Paquete de capacidad de entrada y salida del nivel Standard |
| **Auto-inflate** | Sube unidades automáticamente hasta un tope |
| **Grupo de consumidores** | Una «vista» independiente del flujo con sus propios puntos de control |
| **Punto de control** | «Voy por aquí»; permite continuar tras un reinicio |
| **Capture** | Copia automática del flujo al lago |
| **Ventana tumbling** | Intervalos fijos sin solaparse (cada minuto) |
| **Evento tardío** | Llega cuando su ventana ya cerró |
| **Hot key** | Una clave que concentra el tráfico en una partición |

## 5. Cómo se usa

1. **Planifica** con el planificador y escribe el supuesto en el repositorio.
2. **Crea** con Terraform ([`main.tf`](ejemplos/terraform/main.tf)): namespace con auto-inflate y sin claves locales, event hub con Capture, grupos y roles.
3. **Publica** lotes con claves de cubeta; **lee** con un procesador por instancia (los puntos de control reparten las particiones).
4. **Cierra ventanas** cada pocos segundos y guarda con UPSERT.
5. **Observa** con [`kql-clickstream.md`](ejemplos/kql/kql-clickstream.md) y [`verificar-eventhubs.sh`](ejemplos/cli/verificar-eventhubs.sh). Ejemplos de datos: [`lote-clics.json`](ejemplos/json/lote-clics.json), [`resumen-minuto.json`](ejemplos/json/resumen-minuto.json).

Servicios que se usan: [Event Hubs](../../07-mensajeria/event-hubs-kafka/README.md), [Data Lake Gen2](../../06-storage/data-lake-gen2/README.md), [Redis](../../08-datos/redis/README.md), [identidades](../../02-iam/workload-identity/README.md), [Terraform](../../10-terraform/README.md).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Pipeline de Terraform | Contributor + RBAC Administrator acotado | — |
| **Colector** | — | *Azure Event Hubs Data Sender* en el event hub |
| **Agregador** | — | *Azure Event Hubs Data Receiver* + datos de blob en el contenedor de puntos de control |
| **Namespace (Capture)** | — | *Storage Blob Data Contributor* en el lago |
| Analistas | — | Lector de datos en el lago, solo la zona curada |

| Amenaza | Defensa |
|---|---|
| Datos personales en el flujo | Seudónimos HMAC desde el borde; la sal en Key Vault |
| Un bot inunda el colector | Límite por IP/sesión en APIM o WAF; tope de 100 por lote |
| Claves del namespace filtradas | `local_authentication_enabled = false`: solo Entra ID |
| Lector que lee de más | Rol por event hub, no por namespace |
| Datos eternos | Retención del flujo corta + ciclo de vida en el lago |

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Clave por sesión o cubeta | Clave por página, país o fecha |
| Lotes de hasta 100 | Un `send` por clic |
| Un grupo de consumidores por lector | Dos aplicaciones distintas en el mismo grupo |
| UPSERT del resumen | Incrementar el valor anterior |
| Tolerancia a tardíos y memoria acotada | Ventanas sin límite |
| Lago como fuente de verdad | Confiar solo en el agregador en línea |
| Alertar por limitaciones (429) y retraso | Descubrir el atraso por el tablero vacío |
| Pensar las particiones antes de crear | Esperar a cambiarlas «cuando haga falta» |

## 8. Límites, costos y versiones
- **Costo:** unidades por hora (+ auto-inflate), eventos de entrada, Capture, almacenamiento del lago y de la retención. Lo que más escala es la capacidad: pon un **tope** de auto-inflate.
- El **número de particiones** de un event hub Standard no se puede reducir y cambiarlo tiene restricciones: decídelo con tiempo (verifica en la doc oficial).
- Cuotas (particiones, grupos, retención, tamaño máximo de evento) cambian por nivel: verifica la tabla vigente.
- Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, Azure SDK BOM 1.3.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
