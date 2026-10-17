# AWS · Gobierno · AWS CloudTrail (auditoría de actividad)

**CloudTrail registra, como eventos, cada llamada a la API de AWS en tu cuenta: quién la hizo, desde dónde, cuándo, sobre qué recurso y si funcionó.** Es la «caja negra» y la cámara de seguridad de tu nube: responde a *«¿quién borró esto?»*, *«¿quién abrió ese puerto?»* y *«¿alguien intentó entrar?»*.

## 1. Qué es

**Analogía:** el **libro de visitas con cámara** de un edificio. Cada vez que alguien usa una llave (una llamada a la API) queda anotado: persona o rol, hora, puerta (servicio y acción), si entró o lo rechazaron. Tú decides si el libro se guarda además en una caja fuerte aparte (S3 protegido) que nadie del edificio puede modificar.

```
 Consola · CLI · SDK · servicios ──► API de AWS ──► CloudTrail
                                                       │
            ┌──────────────────────────────────────────┼─────────────────────────┐
            ▼                                          ▼                         ▼
   Historial de eventos                         Trail (traza)               CloudTrail Lake
   (90 días, gratis, solo                       ├─► S3 (archivos .json.gz)   (almacén de datos
    eventos de administración)                  ├─► CloudWatch Logs ─► filtros ─► alarmas    de eventos con SQL)
                                                └─► EventBridge
```

## 2. Cómo funciona por dentro

| Concepto | Qué hace |
|---|---|
| **Evento** | El registro de una llamada: `userIdentity`, `eventTime`, `eventSource`, `eventName`, `awsRegion`, `sourceIPAddress`, `userAgent`, `errorCode`, `requestParameters`… |
| **Eventos de administración** | Plano de control: crear, modificar, borrar recursos, iniciar sesión. Se registran por defecto |
| **Eventos de datos** | Plano de datos: objetos de S3, invocaciones de Lambda, ítems de DynamoDB… **Voluminosos y con costo**: se activan de forma selectiva |
| **Eventos de Insights** | Detectan actividad **inusual** (ritmo de llamadas o de errores) frente a lo normal |
| **Historial de eventos** | Últimos 90 días de eventos de administración, por región, sin configurar nada |
| **Traza (*trail*)** | Entrega continua a S3 (y opcionalmente a CloudWatch Logs y EventBridge); puede ser multirregión y **de toda la organización** |
| **Validación de integridad** | Archivos de resumen firmados que permiten comprobar que los registros no fueron alterados |
| **Archivos de registro** | `AWSLogs/<cuenta>/CloudTrail/<región>/<año>/<mes>/<día>/…json.gz`, con registros dentro de `{"Records":[…]}` |
| **CloudTrail Lake** | Almacén de eventos consultable con SQL, con retención configurable *(verifica el máximo)* |
| **Retraso** | Los eventos suelen aparecer en unos minutos, no al instante *(verifica)* |
| **Tipos de identidad** | `Root`, `IAMUser`, `AssumedRole`, `FederatedUser`, `AWSService`, `IdentityCenterUser`… |
| **Costo** | La primera copia de eventos de administración por región suele ser gratuita; copias adicionales, eventos de datos, Insights y Lake se cobran *(verifica)* |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| «¿Quién hizo este cambio y cuándo?» | **CloudTrail** |
| Detectar uso del usuario raíz, inicios de sesión sin MFA, ráfagas de `AccessDenied` | **CloudTrail** → CloudWatch Logs → alarmas |
| Evidencia de auditoría y forense | **Traza a S3** protegida (+ validación de integridad) |
| Investigar rápido con SQL sobre meses de eventos | **CloudTrail Lake** o **Athena** sobre S3 |
| Saber **cómo está** hoy un recurso y su historial de configuración | No: [Config](../config-reglas/README.md) |
| **Impedir** acciones | No: [SCP](../organizations-scp/README.md) (CloudTrail registra, no bloquea) |
| Registros de **tu aplicación** | No: logs de aplicación |
| Rastrear tráfico de red | No: registros de flujo de la VPC ([red](../../01-red/README.md)) |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Principal** | Quién llama: usuario, rol, servicio, raíz |
| **Plano de control / de datos** | Administrar recursos / usar el contenido de los recursos |
| **Solo lectura (`readOnly`)** | Eventos que no cambian nada (`Describe*`, `List*`, `Get*`) |
| **Traza de organización** | Una traza creada en la cuenta de administración que cubre todas las cuentas; los miembros no pueden apagarla |
| **Cuenta de archivo de registros** | Cuenta aparte donde se guarda el bucket de auditoría |
| **Filtro de métrica** | Regla de CloudWatch que cuenta los registros que coinciden con un patrón |
| **Detección** | Reglas (en código o alarmas) que leen los eventos y avisan |

## 5. Cómo se usa
1. Crea **una traza multirregión** (mejor, de organización) hacia un bucket **en la cuenta de archivo de registros**: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Activa **validación de integridad**, cifrado con KMS y envío a **CloudWatch Logs**.
3. Crea **filtros de métrica y alarmas** para lo crítico: raíz, inicio de sesión sin MFA, `AccessDenied`, cambios de política, cambios en trazas y Config.
4. Activa **eventos de datos** solo donde aportan (por ejemplo, un bucket sensible).
5. Para investigar: historial de eventos (últimos 90 días), **Athena** ([`ejemplos/sql/athena.sql`](ejemplos/sql/athena.sql)) o **CloudTrail Lake**.
6. Automatiza la detección y la búsqueda desde Java ([uso en Java](uso-en-java.md)).
7. Protege la evidencia: bloqueo de objetos, sin borrado, acceso mínimo ([`ejemplos/cli/cloudtrail.sh`](ejemplos/cli/cloudtrail.sh)).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **Servicio CloudTrail** | Rol de servicio hacia CloudWatch Logs | Escribe en S3 y cifra con KMS (política del bucket y de la clave con `aws:SourceArn` de la traza) |
| **Pipeline** | `cloudtrail:CreateTrail`, `UpdateTrail`, `StartLogging`, `PutEventSelectors`, `PutInsightSelectors` | — |
| **Investigador (solo lectura)** | `cloudtrail:LookupEvents`, `DescribeTrails`, `GetTrailStatus` | `s3:GetObject` en el bucket de la traza; `athena:*` acotado |
| **Aplicación de detección** | `cloudtrail:LookupEvents` | `s3:GetObject` en el prefijo de la traza |

- **El bucket de auditoría es evidencia:** cuenta aparte, cifrado con KMS, bloqueo de acceso público, versionado/bloqueo de objetos, y nadie del equipo de aplicaciones puede borrar.
- **Quien vigila no debe poder apagar la cámara:** SCP que impiden `StopLogging`/`DeleteTrail` ([Organizations](../organizations-scp/README.md)).
- Los eventos pueden contener **datos sensibles** (parámetros de solicitud, direcciones IP): limita quién los lee.
- `LookupEvents` solo cubre **administración** y **90 días**; para más, usa la traza o Lake.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Traza multirregión (mejor, de organización) | Depender solo del historial de 90 días |
| Bucket en una cuenta separada, cifrado, con validación | Guardar los registros en la misma cuenta que se audita sin protección |
| Alarmas para raíz, falta de MFA, `AccessDenied`, cambios de trazas | Mirar los registros solo después del incidente |
| Eventos de datos selectivos | Activar eventos de datos en todo y asumir el costo |
| Ventana y umbral en las detecciones (ráfagas) | Alertar por cada `AccessDenied` aislado |
| Consultar con Athena/Lake por rango de fechas | Descargar y leer archivos uno por uno |
| SCP para proteger la traza | Confiar en que «nadie la apagará» |
| Retención acorde a la norma | Borrar los registros para ahorrar |

## 8. Límites, costos y versiones
- **Costo:** eventos de administración (primera copia gratis por región), copias adicionales, **eventos de datos**, Insights, Lake y el almacenamiento/consulta en S3-Athena *(verifica precios)*.
- **Límites** *(verifica)*: `LookupEvents` ≈ 2 solicitudes por segundo por cuenta y región; un atributo de búsqueda por llamada; 50 eventos por página.
- **Terraform:** `aws_cloudtrail`, `aws_cloudtrail_event_data_store`, `aws_s3_bucket(+policy)`, `aws_kms_key`, `aws_cloudwatch_log_group`, `aws_cloudwatch_log_metric_filter`, `aws_cloudwatch_metric_alarm`. Validado con `init` + `validate`.
- **Java:** AWS SDK v2 `cloudtrail` (+ `s3` para leer los archivos).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
