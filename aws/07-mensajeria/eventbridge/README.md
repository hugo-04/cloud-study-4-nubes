# AWS · Mensajería · Amazon EventBridge (bus de eventos)

**EventBridge es un bus de eventos sin servidores: recibe eventos (de tus aplicaciones, de servicios de AWS y de socios SaaS), y unas *reglas* con *patrones* deciden a qué destinos enviar cada uno**, con transformación, reintentos, cola de fallos, archivo y reproducción. Es el «enrutador por contenido»: quien publica no sabe quién escucha, y quien escucha dice qué le interesa.

## 1. Qué es

**Analogía:** la **central de despacho de un puerto**. Cada barco (evento) llega con su manifiesto (JSON). El despachador (bus) consulta las reglas («los contenedores refrigerados van al muelle 3, los que superan 20 toneladas avisan a aduanas») y los envía. Si un muelle está cerrado, reintenta y, si no hay forma, deja el manifiesto en la oficina de pendientes (DLQ). Y guarda copia de todo en un archivo por si hay que reproducir un día.

```
 Tu app ──PutEvents──┐
 Servicios AWS ──────┤        ┌─ regla A (patrón) ──► SQS facturación
 SaaS (socios) ──────┼─► BUS ─┼─ regla B (patrón) ──► SQS logística  (con transformación)
                     │        ├─ regla C (patrón) ──► Step Functions / Lambda / API externa
                     │        └─ archivo ──► reproducción (replay)
```

## 2. Cómo funciona por dentro

| Concepto | Qué hace |
|---|---|
| **Bus de eventos** | Canal que recibe eventos. **Predeterminado** (eventos de servicios de AWS), **personalizado** (los tuyos) y de **socio** (SaaS) |
| **Evento** | JSON con un sobre fijo: `version`, `id`, `detail-type`, `source`, `account`, `time`, `region`, `resources` y `detail` (tu contenido) |
| **Regla** | Un patrón de evento (o un horario) + hasta **5 destinos** *(verifica)* |
| **Patrón de evento** | JSON que describe qué eventos coinciden: valores exactos, `prefix`, `suffix`, `anything-but`, `numeric`, `exists`, `wildcard`, `equals-ignore-case`, `$or` |
| **Destino (*target*)** | Dónde se entrega: SQS, SNS, Lambda, Step Functions, Kinesis, otro bus (otra cuenta o región), API externa (*API destination*), ECS, etc. |
| **Transformador de entrada** | Extrae campos del evento y arma el mensaje que recibe el destino |
| **Política de reintentos** | Por destino: edad máxima del evento (60 s a 24 h) y número de reintentos (0 a 185); por defecto 24 h y 185 *(verifica)* |
| **DLQ del destino** | Cola SQS estándar donde cae lo que no se pudo entregar |
| **Archivo y reproducción** | Guarda eventos (con filtro opcional) y los **reproduce** más tarde hacia el mismo bus |
| **Pipes** | Conexión punto a punto *fuente → filtro → enriquecimiento → destino* (SQS, Kinesis, DynamoDB Streams, Kafka…) |
| **Scheduler** | Servicio hermano para tareas **programadas** (una vez o recurrentes, con zona horaria); mejor que las reglas con cron |
| **Registro de esquemas** | Descubre y guarda los esquemas de tus eventos; genera código para Java |
| **Entrega** | **Al menos una vez** y **sin orden garantizado**: los consumidores deben ser idempotentes |
| **Tamaño** | Hasta 1 MiB por evento *(verifica; antes 256 KiB)* → más grande: [Claim Check](../../06-storage/claim-check/README.md) |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Enrutar por **contenido** (campos del JSON) a varios destinos | **EventBridge** |
| Reaccionar a eventos de **servicios de AWS** (S3, ECS, GuardDuty, cambios de estado) | **EventBridge** (bus predeterminado) |
| Integrar con SaaS o con otra cuenta/equipo con un contrato de eventos | **EventBridge** (bus personalizado + política del bus) |
| Reproducir eventos pasados tras corregir un error | **Archivo y reproducción** |
| Tareas programadas con zona horaria | **Scheduler** |
| Mismo evento a muchas colas con filtros simples y alto volumen | [SNS](../sns/README.md) |
| Un consumidor, con reintentos y backlog | [SQS](../sqs/README.md) |
| Flujo continuo de millones de registros, orden por clave, varios lectores | [Kinesis](../kinesis-data-streams/README.md) o [MSK](../msk-kafka/README.md) |
| Latencia de milisegundos estricta o rendimiento masivo | No: EventBridge añade decenas a cientos de ms *(verifica)* |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Bus** | El «buzón central» al que llegan los eventos |
| **Regla** | «Si el evento se parece a esto, mándalo allá» |
| **Patrón** | La forma del evento que me interesa (no una condición programada) |
| **Destino** | Quien recibe el evento |
| **`source`** | Quién lo emite; `aws.*` está reservado para AWS (usa `modalima.ordenes`) |
| **`detail-type`** | Nombre del hecho: `OrdenCreada` |
| **`detail`** | Tu contenido de negocio |
| **DLQ** | Dónde quedan los eventos que no se pudieron entregar |
| **Replay** | Volver a emitir eventos archivados |
| **Idempotente** | Procesar dos veces el mismo evento da el mismo resultado |

## 5. Cómo se usa
1. Define el **contrato**: `source`, `detail-type`, versión y esquema del `detail` ([`ejemplos/json`](ejemplos/json)).
2. Crea el bus, la **regla**, el **destino** (con reintentos, DLQ y, si hace falta, transformador) y el **archivo**: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
3. Autoriza al destino: la **política de la cola** con `aws:SourceArn` de la regla.
4. **Prueba el patrón** antes de desplegar: `aws events test-event-pattern` ([`ejemplos/cli/eventbridge.sh`](ejemplos/cli/eventbridge.sh)) y el evaluador de [uso en Java](uso-en-java.md).
5. Publica con `PutEvents` en lotes de hasta 10 y **revisa `FailedEntryCount`**.
6. Alarma sobre `FailedInvocations` y la DLQ; consumidores idempotentes.

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **Productor** | — | `events:PutEvents` sobre el **ARN del bus** (no `*`) |
| **Destino SQS/SNS/Lambda** | — | Política del **recurso** que autoriza a `events.amazonaws.com` con `aws:SourceArn` de la regla |
| **Destino con rol** (Step Functions, Kinesis, ECS, API destination) | — | `role_arn` de la regla con permiso mínimo |
| **Pipeline** | `events:PutRule`, `PutTargets`, `CreateEventBus`, `CreateArchive` | — |
| **Otra cuenta** | Política del bus (`aws_cloudwatch_event_bus_policy`) | Solo `events:PutEvents` desde cuentas o la organización |

- **Cifrado:** los eventos se cifran en reposo; puedes usar tu propia clave KMS en el bus *(verifica)*.
- **API destinations:** las credenciales viven en una *conexión* (guardadas en Secrets Manager por el servicio).
- **Datos personales:** no los pongas en el `detail`; se archivan y se registran.
- **Registro:** CloudTrail registra cambios de reglas; usa un destino de CloudWatch Logs para depurar (no en producción con datos sensibles).

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Un bus **por dominio o equipo**, no uno global | Un único bus con cientos de reglas de todos |
| Contrato versionado (`version` en el `detail`) | Cambiar campos sin avisar a quien escucha |
| Destino SQS por consumidor + DLQ del destino | Lambda/API directo sin cola para flujos críticos |
| Política de reintentos acotada (edad y número) | Reintentar 24 h un evento que ya no sirve |
| Probar el patrón con eventos reales | «Creo que coincide» |
| Revisar `FailedEntryCount` en cada `PutEvents` | Asumir que HTTP 200 significa «todos entregados» |
| Archivar eventos de negocio y probar el *replay* | Reproducir sin consumidores idempotentes |
| Scheduler para horarios | Reglas con `cron` en UTC y sorpresas de zona horaria |
| Eventos pequeños con referencia a datos grandes | Meter archivos o listas enormes en el `detail` |

## 8. Límites, costos y versiones
- **Costo:** por millón de eventos personalizados publicados; los eventos de servicios de AWS en el bus predeterminado son gratuitos; cargo adicional por archivo/reproducción, *API destinations*, Pipes y Scheduler *(verifica en la página de precios)*.
- **Límites** *(verifica)*: reglas por bus, destinos por regla (5), entradas por `PutEvents` (10), tamaño del evento, cuotas de invocación por región.
- **Terraform:** `aws_cloudwatch_event_bus`, `aws_cloudwatch_event_rule`, `aws_cloudwatch_event_target`, `aws_cloudwatch_event_archive`, `aws_cloudwatch_event_bus_policy`, `aws_scheduler_schedule`. Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
