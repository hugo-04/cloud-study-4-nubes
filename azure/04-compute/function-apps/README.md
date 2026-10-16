# Azure · Compute · Function Apps (Azure Functions)

## 1. Qué es

**Azure Functions te deja ejecutar un trozo de código cuando ocurre algo** (llega un mensaje, se sube un archivo, suena un reloj, entra una petición HTTP) **sin administrar servidores.** Pagas por ejecución y por recursos usados (según el plan), y la plataforma crea o apaga instancias según la demanda.

Analogía: un **taxi por viaje**. No compras el auto ni pagas el garaje: pides el viaje cuando lo necesitas.

| Palabra | Significado |
|---|---|
| **Function App** | El contenedor de despliegue: agrupa varias funciones que se escalan y se configuran juntas |
| **Function** | Un método Java con un **trigger** (qué lo dispara) y, opcionalmente, **bindings** (entradas/salidas) |
| **Trigger** | El evento que inicia la función. Cada función tiene **exactamente uno** |
| **Binding** | Conexión declarativa: "leer este blob", "escribir en esta cola" sin código de cliente |

---

## 2. Cómo funciona por dentro

```
 Evento (mensaje, blob, timer, HTTP…)
        │
        ▼
 ┌─ Scale controller (decide cuántas instancias hay) ─┐
 │  mira la longitud de cola / eventos pendientes      │
 └───────────────┬─────────────────────────────────────┘
                 ▼
   Instancia  =  Host de Functions  +  Worker de Java (tu código)
        │               │
        │               └─ extensiones: Service Bus, Event Hubs, Blob, Timer…
        ▼
   Storage account del host (AzureWebJobsStorage):
     claves, leases (singleton del timer), checkpoints, estado de Durable
```

### 2.1 Piezas
- **Host de Functions:** el proceso de la plataforma que escucha los triggers, administra concurrencia, reintentos y checkpoints. Habla con tu código por gRPC.
- **Worker de Java:** el proceso donde corre tu método anotado.
- **Extensiones (bundles):** las bibliotecas que implementan cada trigger/binding.
- **Cuenta de Storage del host:** guarda claves de las funciones, *leases* (coordinación entre instancias), progreso de los consumidores y estado de Durable. Si no hay acceso a ella, **el host no arranca**.
- **Scale controller:** observa la fuente del evento (cola, partición, etc.) y decide cuántas instancias necesitas; con carga cero puede bajar a cero (según el plan).

### 2.2 Planes de alojamiento

| Plan | Idea | Escala a cero | VNet | Arranque en frío | Cuándo |
|---|---|---|---|---|---|
| **Flex Consumption** | Serverless moderno: escala **por función**, memoria de instancia elegible, *always-ready* configurable | Sí | Sí | Mitigable con instancias siempre listas | **Opción por defecto** para nuevos proyectos |
| **Premium (Elastic)** | Instancias **pre-calentadas** + escala elástica | No (mínimo configurable) | Sí | Casi inexistente | Latencia estable, tareas largas |
| **Dedicated (App Service plan)** | Reutiliza el plan de App Service | No | Sí | No aplica con Always On | Ya tienes un plan con capacidad libre |
| **Consumption clásico** | Serverless original | Sí | Limitado | Notable | Existente; planea migrar (hay anuncios de retiro para Linux: *verifica*) |
| **Container Apps** | Hospeda Functions como contenedor | Sí | Sí | Depende | Quieres un único entorno de contenedores |

*Planes, límites y fechas de retiro cambian: verifica en la documentación oficial.*

### 2.3 Triggers más usados (con la anotación Java)

| Trigger | Anotación | Semántica |
|---|---|---|
| HTTP | `@HttpTrigger` | Petición/respuesta; límite de ~230 s por el balanceador |
| Timer | `@TimerTrigger` | Expresión NCRONTAB de 6 campos; **una sola ejecución a la vez entre instancias** (usa un *lease*) |
| Service Bus (cola/tema) | `@ServiceBusQueueTrigger` / `@ServiceBusTopicTrigger` | *Peek-lock*; si falla, reintenta y luego va a la cola de mensajes fallidos (DLQ) |
| Storage Queue | `@QueueTrigger` | Reintenta hasta 5 veces y mueve a `<cola>-poison` |
| Blob | `@BlobTrigger` | Con `source = "EventGrid"` reacciona **rápido y de forma fiable**; el modo por sondeo puede tardar |
| Event Grid | `@EventGridTrigger` | Un evento por invocación |
| Event Hubs | `@EventHubTrigger` | Lotes por partición con *checkpoint*; ver [Event Hubs](../../07-mensajeria/event-hubs-kafka/README.md) |
| Cosmos DB | `@CosmosDBTrigger` | Change feed: cambios del contenedor |

Salidas habituales: `@ServiceBusQueueOutput`, `@QueueOutput`, `@BlobOutput`, `@EventHubOutput`, `@CosmosDBOutput` (con `OutputBinding<T>` o como valor de retorno).

### 2.4 Semántica de entrega: **al menos una vez**
La plataforma garantiza que cada evento se procesa **al menos una vez**, no exactamente una. Un reinicio, un timeout o una excepción pueden repetir la invocación. Por eso **toda función debe ser idempotente**: procesar dos veces el mismo mensaje no debe dañar nada (clave de idempotencia, `upsert`, tabla de deduplicación).

### 2.5 Reintentos y mensajes envenenados
- **Reintentos del trigger** (p. ej. Service Bus): el mensaje vuelve a la cola hasta `maxDeliveryCount` y entonces va a la **DLQ**.
- **Directiva de reintento de la función:** `@FixedDelayRetry` / `@ExponentialBackoffRetry` (para triggers que lo soportan) reintentan dentro del host antes de rendirse.
- **Mensaje envenenado (*poison*)**: el que siempre falla. Debe terminar en una DLQ con alerta, no en un bucle infinito.

### 2.6 Tiempos y concurrencia
- Tiempo máximo de una ejecución (`functionTimeout` en `host.json`) depende del plan; no es infinito en todos. *Verifica por plan.*
- Cada instancia procesa varios mensajes **en paralelo** (`maxConcurrentCalls` en Service Bus, por ejemplo). Más paralelismo = más rápido y más presión sobre tus dependencias.
- Con **Target-Based Scaling**, la plataforma escala según el backlog real.

### 2.7 Durable Functions: orquestaciones con estado
Para flujos largos o con esperas (aprobaciones, sagas):
- **Orchestrator:** función **determinista** que coordina; se **re-ejecuta (replay)** desde el historial en cada paso. No uses relojes, aleatorios, ni I/O dentro de ella.
- **Activity:** función normal que hace el trabajo real (I/O).
- **Client:** inicia y consulta orquestaciones.
- Patrones: **encadenado**, **fan-out/fan-in**, **API asíncrona (202 + estado)**, **monitor**, **interacción humana** (espera de evento externo con *timeout*).
- El estado vive en el *task hub* (Storage u otro proveedor).

### 2.8 Identidad y conexiones (sin cadenas de conexión)
Las conexiones por identidad usan el sufijo `__`:

| App setting | Significado |
|---|---|
| `AzureWebJobsStorage__accountName=stfunc01` | El host usa Storage con la identidad de la app |
| `SBCONN__fullyQualifiedNamespace=sb-modalima.servicebus.windows.net` | Conexión `SBCONN` a Service Bus por identidad |
| `STORAGE_FOTOS__blobServiceUri=https://stfotos.blob.core.windows.net` | Conexión a Blob por identidad |
| `X__clientId=<clientId>` / `X__credential=managedidentity` | Elegir una identidad user-assigned concreta |

Roles que necesita la identidad (ejemplos):

| Para | Rol |
|---|---|
| Host: blobs, colas, tablas | *Storage Blob Data Owner*, *Storage Queue Data Contributor*, *Storage Table Data Contributor* |
| Recibir de Service Bus | *Azure Service Bus Data Receiver* |
| Enviar a Service Bus | *Azure Service Bus Data Sender* |
| Leer/escribir blobs | *Storage Blob Data Reader / Contributor* |
| Event Hubs | *Azure Event Hubs Data Receiver / Sender* |

### 2.9 Seguridad de HTTP
`authLevel`: `ANONYMOUS`, `FUNCTION` (clave por función), `ADMIN` (clave maestra). Las **claves** son un secreto compartido que viaja en un encabezado; sirven para integraciones simples, **no** para identificar usuarios. Para APIs reales: nivel `ANONYMOUS` en la función + **autenticación de la plataforma con Entra ID** (Easy Auth) o validación del token en tu código.

### 2.10 Red
Entrada: access restrictions o Private Endpoint (`privatelink.azurewebsites.net`, subrecurso `sites`). Salida: VNet Integration (Flex y Premium) para llegar a recursos privados. Las **conexiones de los triggers** (Service Bus, Storage) también necesitan ruta de red si esos recursos están privados; en Premium/Flex esto se gestiona con "virtual network triggers".

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- Reaccionar a eventos: archivo subido, mensaje en cola, cambio en la base.
- Tareas cortas y programadas (timer): resumen diario, limpieza, sincronización.
- Webhooks y APIs ligeras con tráfico irregular.
- Orquestaciones de larga duración (Durable).
- Pegamento entre servicios.

| NO lo uses si | Alternativa |
|---|---|
| Procesos de horas en una sola ejecución con estado en memoria | Container Apps job / AKS |
| API con tráfico alto y constante y latencia mínima exigida | [App Service](../app-service/README.md) o [Container Apps](../container-apps/README.md) |
| Necesitas control fino del runtime, sidecars o mallas | [AKS](../aks/README.md) |
| La lógica es un monolito grande | App Service |
| Tu equipo necesita ejecutar el mismo código como servicio y como función | Container Apps (mismo contenedor) |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Trigger** | Lo que dispara la función | Mensaje en `pedidos` |
| **Binding** | Entrada/salida declarativa | Escribir en la cola `facturas` |
| **Cold start** | Demora de la primera ejecución sin instancias activas | 2–5 s en Java sin precalentar |
| **Always-ready** | Instancias que se mantienen encendidas | 2 instancias en Flex |
| **Scale controller** | Decide cuántas instancias hay | Más mensajes → más instancias |
| **Lease** | Candado compartido en Storage | Timer: una ejecución a la vez |
| **Checkpoint** | Marca de hasta dónde procesaste | Event Hubs / Cosmos |
| **Idempotencia** | Repetir no cambia el resultado | `upsert` por `pedidoId` |
| **DLQ** | Cola de mensajes fallidos | `pedidos/$deadletterqueue` |
| **host.json** | Configuración del host (tiempos, concurrencia) | `maxConcurrentCalls` |
| **Task hub** | Almacén del estado de Durable | Tablas/colas en Storage |
| **Orquestador** | Coordinador determinista (Durable) | Saga de pedido |

---

## 5. Cómo se usa

### 5.1 Crear una Function App en Flex Consumption (CLI)
```bash
az storage account create -g rg-estudio-compute -n stfuncmodalima01 -l eastus2 --sku Standard_LRS --allow-shared-key-access false
az functionapp create -g rg-estudio-compute -n func-modalima01 \
  --storage-account stfuncmodalima01 \
  --flexconsumption-location eastus2 \
  --runtime java --runtime-version 21 \
  --instance-memory 2048 --maximum-instance-count 40
```
Guion completo (identidad, roles, app settings por identidad, VNet, always-ready): [ejemplos/cli/function-apps.sh](ejemplos/cli/function-apps.sh). Terraform: [ejemplos/terraform/main.tf](ejemplos/terraform/main.tf).

### 5.2 Desarrollo local
```bash
# Herramientas: Azure Functions Core Tools + Azurite (emulador de Storage)
func init --worker-runtime java
func new --template "Service Bus Queue trigger" --name ProcesarPedido
mvn clean package
mvn azure-functions:run          # o: func start
```
`local.settings.json` (no se sube a Git): ver [ejemplos/java/local.settings.json](ejemplos/java/local.settings.json). Para desplegar: `mvn azure-functions:deploy` o `func azure functionapp publish`.

### 5.3 Estructura de un proyecto Java
```
src/main/java/.../Funciones.java     ← métodos @FunctionName
host.json                            ← concurrencia, timeouts, extensiones
local.settings.json                  ← solo local
pom.xml                              ← azure-functions-java-library + plugin Maven
```
El plugin Maven genera el `function.json` de cada función a partir de las anotaciones.

### 5.4 Cómo comprobar que quedó bien
```bash
az functionapp show -g <rg> -n <func> --query "{estado:state, plan:kind}" -o json
az functionapp function list -g <rg> -n <func> -o table
az functionapp config appsettings list -g <rg> -n <func> -o table      # sin valores sensibles en el reporte
# Registros: Application Insights → Live Metrics / transaction search
```

---

## 6. Seguridad

| Tema | Qué hacer |
|---|---|
| **Almacenamiento del host** | Identidad (`AzureWebJobsStorage__accountName`), `allowSharedKeyAccess = false` |
| **Conexiones de triggers** | Identidad con rol de datos mínimo; sin cadenas de conexión |
| **HTTP** | `ANONYMOUS` + Entra ID (Easy Auth) o JWT; las claves de función solo para integraciones técnicas |
| **Red** | Private Endpoint de entrada si es interna; VNet Integration de salida; DNS privado |
| **Secretos** | Referencias a Key Vault |
| **Código desplegado** | Paquete desde un contenedor de Blob con identidad (Flex); despliegue con OIDC |
| **Claves** | Rotación periódica; no las pongas en el código ni en URLs compartidas |

### IAM de este servicio

| Quién | Qué hace | Rol mínimo |
|---|---|---|
| Pipeline | Publicar la función | *Website Contributor* sobre la Function App |
| Función | Consumir/enviar mensajes | Roles **de datos** de cada servicio |
| Operador | Ver logs | *Monitoring Reader* |

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- **Idempotencia** en todo: asume duplicados.
- Funciones **cortas y con una responsabilidad**; lo largo, a Durable o a un job.
- Reutilizar clientes (SDK, HTTP, base de datos) en campos `static`: no los crees por invocación.
- Definir **DLQ, reintentos y alertas** para mensajes envenenados.
- Medir el cold start y elegir el plan por resultados (Flex con *always-ready*, o Premium).
- Poner límites de concurrencia para **no aplastar** a la base de datos downstream.
- Identidad administrada en todo; `local.settings.json` fuera de Git.

**Qué NO hacer**
- Escribir una función que se **dispare a sí misma** (escribe un blob que la vuelve a disparar).
- Código no determinista dentro de un orquestador Durable (hora, `UUID.randomUUID()`, I/O).
- Ejecuciones de horas dentro de una función "normal".
- Dejar claves de función en el repositorio o en el front-end.
- Guardar estado en memoria entre invocaciones esperando que persista.
- Ignorar los reintentos: sin DLQ, un mensaje malo puede consumir dinero en bucle.
- Usar el sondeo de blobs para flujos críticos (usa Event Grid).

---

## 8. Límites, costos y versiones
- Facturación: depende del plan (Flex: por ejecución, GB-segundo y *always-ready*; Premium: instancias reservadas; Dedicated: el plan). *Verifica precios y cuotas gratuitas.*
- Java soportado: 8/11/17/21 (según plan y versión del runtime; **runtime v4**). Verifica `az functionapp list-flexconsumption-runtimes`.
- Tamaño máximo del paquete, tiempo de ejecución y escala máxima por plan: consulta los límites oficiales.
- Bibliotecas de estos ejemplos: `azure-functions-java-library` 3.2, `durabletask-azure-functions` 1.6.

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
