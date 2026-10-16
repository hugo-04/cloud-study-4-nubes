# Azure · Datos · Azure Cosmos DB (API para NoSQL)

## 1. Qué es

**Es una base de datos de documentos JSON, administrada y distribuida globalmente, diseñada para responder en pocos milisegundos a cualquier escala.** Guardas documentos (JSON) en **contenedores**; Azure los reparte automáticamente en muchos servidores según una **clave de partición** que tú eliges, y te cobra por el esfuerzo que cada operación consume, medido en **Unidades de Solicitud (RU, *Request Units*)**, no por servidor.

Cosmos DB ofrece varias "APIs" (NoSQL nativa, MongoDB, Cassandra, Gremlin, Table, PostgreSQL distribuido). **En estos apuntes hablamos de la API para NoSQL** (la nativa, la más completa y la que usa el SDK `azure-cosmos`). *Si tu equipo ya tiene aplicaciones MongoDB o Cassandra, las otras APIs existen; verifica su estado en la documentación.*

Analogía: **una bodega gigante con miles de casilleros etiquetados**. La etiqueta de cada casillero es la *clave de partición* (por ejemplo, el número de cliente). Para sacar algo, dices el casillero y el objeto: es rapidísimo. Si pides "todos los objetos rojos de toda la bodega", alguien tiene que revisar todos los casilleros: se puede, pero cuesta más esfuerzo (más RU). Azure agrega bodegas nuevas solo cuando hace falta, pero **tú decides cómo se etiqueta**, y esa decisión es la más importante del servicio.

```
  Cuenta  (cosmos-modalima.documents.azure.com · regiones · consistencia por defecto · red · autenticación)
   └── Base de datos  (pedidos-db)
        ├── Contenedor  "pedidos"    clave de partición: /clienteId   · throughput: autoscale 1000–10000 RU/s
        │     ├── partición lógica clienteId="C-001"  → [ pedido P-1, pedido P-2, ... ]   (≤ 20 GB)
        │     ├── partición lógica clienteId="C-002"  → [ pedido P-9, ... ]
        │     └── ...   (Azure agrupa miles de particiones lógicas en pocas PARTICIONES FÍSICAS)
        ├── Contenedor  "carritos"   clave: /clienteId   · TTL 7 días
        └── Contenedor  "leases"     clave: /id          · estado del procesador del change feed

  Cada partición física = 4 réplicas (quórum) en la región ──► y se copia en las demás regiones de la cuenta
```

---

## 2. Cómo funciona por dentro

### 2.1 La jerarquía: cuenta → base → contenedor → elemento
- **Cuenta:** el recurso de Azure. Define el *endpoint* (`https://<cuenta>.documents.azure.com`), las **regiones**, el nivel de **consistencia por defecto**, la **red** y la **autenticación**.
- **Base de datos:** agrupación lógica de contenedores (puede compartir rendimiento entre ellos).
- **Contenedor:** donde viven los documentos. Aquí se define la **clave de partición**, la **política de indexación**, el **TTL**, las **claves únicas** y el **rendimiento** (RU/s).
- **Elemento (*item*):** un documento JSON de **hasta 2 MB**. Su identidad real es la pareja **`id` + valor de la clave de partición**. Dos documentos pueden tener el mismo `id` si están en particiones lógicas distintas.
- Propiedades que Cosmos añade solas: `_etag` (versión para concurrencia), `_ts` (marca de tiempo de la última modificación, en segundos), `_rid`, `_self`.
- **Tipos:** JSON no tiene fechas ni decimales exactos. Guarda **fechas como texto ISO-8601** (`2026-10-16T14:05:00Z`) y **dinero como enteros en la unidad menor** (`totalCentimos`): los números son `double` de 64 bits y los decimales pueden perder precisión.

### 2.2 Particionamiento (lo más importante)
| Concepto | Qué es | Límite |
|---|---|---|
| **Partición lógica** | Todos los documentos con el **mismo valor** de clave de partición | **20 GB** de datos; las transacciones solo existen dentro de una |
| **Partición física** | Unidad interna de Azure (servidores y disco) que aloja muchas particiones lógicas; la administra Azure y se **divide sola** al crecer | **10 000 RU/s** por partición física (el almacenamiento físico es del orden de decenas de GB; *verifica el valor vigente*) |

**Cómo elegir la clave de partición** (se decide al crear el contenedor y **no se puede cambiar** sin migrar los datos):
1. **Alta cardinalidad:** muchos valores distintos (`clienteId`, `tenantId`, `dispositivoId`). Evita claves con pocos valores (`pais`, `estado`).
2. **Distribución pareja:** que lecturas **y** escrituras se repartan; una clave "caliente" (todos los pedidos de hoy en `fecha`) satura una sola partición y da errores **429** aunque el resto esté libre.
3. **Presente en tus consultas frecuentes:** la consulta que incluye la clave va a **una** partición; la que no, hace *fan-out* a todas (más RU y más latencia).
4. **Incluida en las lecturas puntuales:** una *lectura puntual* (`id` + clave) es lo más barato que existe (≈ 1 RU para 1 KB).

**Claves jerárquicas** (hasta 3 niveles, por ejemplo `/tenantId`, `/clienteId`, `/pedidoId`): permiten superar el límite de 20 GB de un inquilino grande y repartir mejor; las consultas con prefijo de la clave van dirigidas a un subconjunto de particiones.

Regla práctica: **piensa primero en tus consultas, luego en la clave**. Un documento = un *agregado* (el pedido con sus líneas), y la clave suele ser el dueño del agregado.

### 2.3 Rendimiento: las Unidades de Solicitud (RU)
- Una **RU** es la moneda que mide CPU, memoria y E/S de una operación. Aproximadamente: **lectura puntual de 1 KB ≈ 1 RU**; una escritura de 1 KB ≈ 5 RU o más (crece con el tamaño y con el número de propiedades indexadas); una consulta cuesta según los documentos que revisa y devuelve. **Cada respuesta del SDK te dice cuántas RU gastó** (`getRequestCharge()`).
- Si superas las RU/s disponibles, Cosmos responde **HTTP 429** ("demasiadas solicitudes") con `retry-after`; el SDK reintenta solo, pero si persiste, tu aplicación se ralentiza.

| Modo | Cómo funciona | Cuándo |
|---|---|---|
| **Manual (aprovisionado)** | Fijas un número de RU/s (mínimo 400 por contenedor dedicado) | Carga constante y predecible |
| **Autoscale** | Fijas un máximo (Tmax, mínimo 1 000); Cosmos escala entre 10 % de Tmax y Tmax; **pagas al menos el 10 % de Tmax** por hora | Cargas con picos (la mayoría de microservicios) |
| **Serverless** | Sin RU/s aprovisionadas; **pagas por las RU que consumes**; una sola región; límites de rendimiento menores | Desarrollo, cargas pequeñas e intermitentes |

- **Dedicado** (por contenedor) o **compartido** (por base de datos: los contenedores se reparten las RU). El compartido ahorra, pero un contenedor ruidoso afecta a los demás.
- **Capa gratuita:** 1 000 RU/s y 25 GB gratis, una cuenta por suscripción (se elige al crearla).
- El rendimiento por partición física está limitado a 10 000 RU/s: con 100 000 RU/s necesitas al menos 10 particiones físicas **bien repartidas**.

### 2.4 Niveles de consistencia
Cosmos te deja elegir cuánta frescura exige una lectura a cambio de latencia y costo (la cuenta tiene un nivel por defecto; cada solicitud puede *relajarlo*, nunca fortalecerlo).

| Nivel | Garantía | Cuándo |
|---|---|---|
| **Strong** | Siempre ves la última escritura confirmada (lecturas lineales) | Finanzas críticas; más latencia; no con escrituras en varias regiones |
| **Bounded staleness** | Lecturas atrasadas como máximo *K* versiones o *T* tiempo | Multi-región con retraso acotado |
| **Session** *(por defecto)* | Lees tus propias escrituras y en orden, dentro de una "sesión" (token) | La mayoría de aplicaciones |
| **Consistent prefix** | Nunca ves escrituras fuera de orden | Feeds, historiales |
| **Eventual** | Sin garantía de orden; el más barato y rápido | Contadores, "me gusta" |

> En microservicios sin estado, "sesión" significa **propagar el token de sesión** entre instancias (cabecera) si necesitas leer lo que otra instancia escribió; si no, el balanceador puede llevarte a una réplica atrasada. Ver [uso en Java](uso-en-java.md), sección 3.

### 2.5 Indexado y TTL
- Por defecto Cosmos **indexa todas las propiedades** de cada documento automáticamente (sin esquema). Eso hace las consultas flexibles, pero **cada propiedad indexada encarece las escrituras**.
- La **política de indexación** del contenedor permite:
  - **Excluir** rutas que nunca filtras (`/descripcion/*`, `/lineas/*/notas/*`) → escrituras más baratas.
  - **Índices compuestos** para `ORDER BY` con varias propiedades o filtros combinados.
  - **Índices espaciales** y **vectoriales** (búsqueda por similitud; *verifica las funciones vigentes*).
  - Modo de indexación `consistent` (siempre) o `none`.
- **TTL (*time to live*):** `defaultTtl` en el contenedor y `ttl` por documento; Cosmos borra solo los vencidos (consume RU sobrantes). Ideal para carritos, sesiones, tokens y datos temporales.
- **Claves únicas:** garantizan unicidad **dentro de cada partición lógica** (no en todo el contenedor).

### 2.6 El *change feed* (el registro de cambios)
Es un **registro ordenado de los documentos creados o modificados** de un contenedor, que puedes leer sin consultar y sin cargar el contenedor principal. Es la base de muchos patrones de microservicios.

- **Quién lo lee:** el **procesador del change feed** (SDK de Java), el *trigger* de Azure Functions, o el modelo *pull* (lees tú con tu propio puntero).
- **Cómo funciona el procesador:** un **contenedor de arrendamientos** (*lease container*) guarda el progreso por rango de particiones; varias instancias con el mismo nombre de procesador se **reparten los rangos** y reequilibran al entrar o salir; cada rango lo atiende **una sola instancia a la vez**.
- **Garantía:** **al menos una vez** (*at-least-once*): si tu código falla, el lote se reintenta, así que tu manejador debe ser **idempotente**.
- **Modo "última versión" (por defecto):** ves el estado más reciente de cada documento cambiado; **no ves los borrados**. Para eliminaciones: borrado lógico (`eliminado: true`) + TTL. Existe un modo "todas las versiones y eliminaciones" que exige copia continua (*verifica su estado vigente*).
- **Costo:** leer el feed y actualizar los arrendamientos consume RU.
- **Usos:** **Outbox transaccional** (escribes el pedido y el evento en el mismo lote, el feed publica el evento), **proyecciones CQRS**, sincronizar un buscador o caché, auditoría, notificaciones.

### 2.7 Transacciones y concurrencia
- **ACID dentro de una partición lógica:** mediante **lote transaccional** (*transactional batch*: hasta 100 operaciones, todas con la misma clave, todo o nada) o procedimientos almacenados en JavaScript. **No hay transacciones entre particiones ni entre contenedores.**
- **Concurrencia optimista con ETag:** al reemplazar, envías `If-Match: <_etag>`; si alguien cambió el documento, recibes **412** y vuelves a leer. Evita "el último en escribir gana".
- **Actualización parcial (*patch*):** modificas campos concretos (`set`, `replace`, `add`, `remove`, `increment`) sin reenviar el documento completo (ahorra RU y evita conflictos de campos distintos).

### 2.8 Distribución global
- Añadir una **región** es un clic: Cosmos replica los datos y tú eliges el orden de **prioridad de conmutación** (*failover priority*).
- **Escritura en una región** (por defecto) + lecturas en todas, o **escritura multiregión** (*multi-write*): cualquier región acepta escrituras, con **resolución de conflictos** (última escritura gana por `_ts`, o política personalizada). Multi-write no admite consistencia *Strong*.
- **Zonas de disponibilidad** por región (*zone redundancy*): réplicas repartidas en zonas.
- **Conmutación automática** (*automatic failover*) activable: si una región cae, Cosmos promueve otra. El SDK usa **regiones preferidas** y reintenta contra otra región.
- SLA de disponibilidad más alto con varias regiones o zonas (*verifica los valores vigentes*).

### 2.9 Copias y restauración
| Modo | Qué ofrece |
|---|---|
| **Periódica** (por defecto) | Copias cada cierto intervalo (por defecto 4 h) con retención corta; la restauración se pide a soporte |
| **Continua** (7 o 30 días) | **Restauración a un instante** (PITR) que tú mismo lanzas, creando una **cuenta nueva**; permite recuperar contenedores/bases borrados |

*Verifica niveles de retención, regiones soportadas y restricciones (no todas las configuraciones permiten pasar de un modo a otro).*

### 2.10 Red y autenticación
- **Red:** *Private Endpoint* (subrecurso `Sql`, zona DNS `privatelink.documents.azure.com`), reglas de firewall por IP o puntos de conexión de servicio, y **acceso a red pública desactivable**.
- **Autenticación:**
  - **Claves** (primaria/secundaria): dan acceso total; son secretos que hay que rotar. **Se pueden desactivar** (`disableLocalAuth`).
  - **Microsoft Entra ID + RBAC del plano de datos:** identidad administrada → **roles de Cosmos** (no son los roles normales de Azure): *Cosmos DB Built-in Data Reader* (`…0001`) y *Built-in Data Contributor* (`…0002`), o roles personalizados con acciones concretas.
- El acceso al **plano de control** (crear cuentas/contenedores) se gobierna con Azure RBAC normal. **Un *Owner* de Azure no puede leer documentos** si no tiene un rol de datos.

### 2.11 Cómo se conecta el SDK
- **Modo Directo (TCP)** (por defecto en Java): menor latencia, usa puertos 10250–10255 hacia las réplicas; con Private Endpoint hay que permitir esos puertos.
- **Modo Gateway (HTTPS 443):** un solo puerto, algo más de latencia; útil con firewalls estrictos o en el emulador.
- **Un solo cliente por aplicación** (*singleton*): abrir un cliente por solicitud agota conexiones y es lentísimo.
- **Regiones preferidas** (`preferredRegions`) y reintentos ante 429 (hasta 9 reintentos/30 s por defecto en el SDK de Java; *verifica*).

### 2.12 Observabilidad
- **Métricas:** *Normalized RU Consumption* (¿hay partición caliente?), solicitudes por código de estado (429, 408, 503), latencia del servidor, almacenamiento.
- **Registros de diagnóstico** a Log Analytics (modo específico del recurso): `CDBDataPlaneRequests`, `CDBPartitionKeyRUConsumption`, `CDBQueryRuntimeStatistics`, `CDBPartitionKeyStatistics`.
- En cada respuesta del SDK: **`getRequestCharge()`** y **`getDiagnostics()`** (para soporte y para depurar latencia).
- Ver [KQL](ejemplos/kql/kql-cosmos.md).

### 2.13 Capacidades recientes (confirma el estado antes de depender de ellas)
Búsqueda **vectorial** y de **texto completo**, *mirroring* hacia Microsoft Fabric para analítica sin ETL, y **claves de partición jerárquicas**. Evolucionan rápido: revisa la documentación del momento.

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- **Catálogos, carritos, perfiles, sesiones, preferencias**: lecturas por clave con latencia de milisegundos.
- **Un documento por agregado** (DDD): el pedido con sus líneas, sin `JOIN`s.
- **Multi-inquilino** (`/tenantId`) y **IoT/telemetría** con volúmenes grandes por dispositivo.
- **Disponibilidad global**: usuarios en varias regiones con baja latencia.
- **Outbox y proyecciones** con el change feed.
- **Datos con esquema cambiante** (atributos distintos por producto).

| NO lo uses si | Alternativa |
|---|---|
| Necesitas `JOIN`s complejos, informes ad hoc o integridad referencial fuerte | **Azure SQL** o **PostgreSQL** |
| Necesitas transacciones entre muchas entidades | Base relacional o *sagas* |
| Haces analítica pesada sobre todo el contenedor | Exportar/*mirroring* a un almacén analítico |
| Guardas archivos o documentos de más de 2 MB | **Blob Storage** + referencia en el documento |
| Quieres caché efímera por clave | **Redis** |
| Tu carga es diminuta y estable y no necesitas escala | Una base relacional pequeña es más barata |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **RU (Request Unit)** | Moneda del costo de una operación | Lectura puntual de 1 KB ≈ 1 RU |
| **Clave de partición** | Propiedad que decide en qué "casillero" cae cada documento | `/clienteId` |
| **Partición lógica** | Todos los documentos con el mismo valor de clave (máx. 20 GB) | `clienteId = "C-001"` |
| **Partición física** | Infraestructura interna que aloja muchas lógicas (máx. 10 000 RU/s) | La administra Azure |
| **Lectura puntual** | Leer por `id` + clave de partición | La operación más barata |
| **Consulta entre particiones** (*fan-out*) | Consulta sin la clave: visita todas | Más RU y latencia |
| **Partición caliente** | Una partición recibe más tráfico del que soporta | 429 con RU libres en el resto |
| **Autoscale / Serverless** | Rendimiento elástico / pago por consumo | Picos de campaña |
| **Consistencia** | Qué tan fresca es una lectura | *Session* por defecto |
| **ETag** | Versión del documento para concurrencia optimista | `If-Match` → 412 |
| **Change feed** | Registro de cambios por partición | Outbox, proyecciones |
| **Contenedor de arrendamientos** | Guarda el progreso del procesador del change feed | `leases` |
| **TTL** | Borrado automático por antigüedad | Carritos de 7 días |
| **Clave única** | Unicidad dentro de la partición lógica | `/correo` por `tenantId` |
| **Lote transaccional** | Hasta 100 operaciones atómicas en una partición lógica | Pedido + evento Outbox |
| **Clave jerárquica** | Partición por 2–3 niveles de propiedades | `/tenantId`, `/clienteId` |
| **RBAC de datos** | Roles de Cosmos sobre documentos | *Built-in Data Contributor* |
| **Modo Directo / Gateway** | TCP a las réplicas / HTTPS por puerta de enlace | Directo = menor latencia |

---

## 5. Cómo se usa

1. **Modela por consultas, no por tablas:** lista las 5–10 consultas más frecuentes y define el documento (agregado) y la **clave de partición** que las hace baratas. Decide qué se **incrusta** (líneas del pedido) y qué se **referencia** (catálogo de productos que cambia aparte).
2. **Crea la cuenta:** una región (o dos con zonas), consistencia *Session*, **claves locales desactivadas**, red privada, copia continua si aplica.
3. **Crea la base y los contenedores:** clave de partición (versión 2 para claves grandes/jerárquicas), **política de indexación** (excluye lo que no filtras), TTL, claves únicas, **autoscale**. Añade el contenedor `leases` si usarás change feed.
4. **Da permisos de datos** a cada identidad administrada (rol *Data Reader* o *Data Contributor* acotado a la base o al contenedor).
5. **Conecta desde Java:** cliente único con `DefaultAzureCredential`, modo directo, `preferredRegions`, y mide `getRequestCharge()` en pruebas.
6. **Diseña las escrituras:** `id` determinista (idempotencia), ETag en actualizaciones concurrentes, `patch` para cambios parciales, lote transaccional para pedido + evento.
7. **Consume cambios** con el procesador del change feed (manejador idempotente) para publicar eventos o actualizar proyecciones.
8. **Observa:** *Normalized RU Consumption*, 429, latencia; alertas; revisa consultas caras en los registros.

Archivos: [Terraform](ejemplos/terraform/main.tf) · [CLI](ejemplos/cli/cosmos-db.sh) · [JSON](ejemplos/json/) · [Consultas](ejemplos/consultas/consultas-cosmos.md) · [KQL](ejemplos/kql/kql-cosmos.md).

Ejemplo de documento (pedido como agregado, clave `/clienteId`):

```json
{
  "id": "PED-2026-000123",
  "clienteId": "C-001",
  "tipo": "pedido",
  "estado": "PAGADO",
  "totalCentimos": 35980,
  "moneda": "PEN",
  "lineas": [
    { "sku": "POL-ROJO-M", "cantidad": 2, "precioCentimos": 8990 },
    { "sku": "JEA-AZUL-32", "cantidad": 1, "precioCentimos": 17999 }
  ],
  "creadoEn": "2026-10-16T14:05:00Z"
}
```

---

## 6. Seguridad

- **Desactiva las claves** (`local_authentication_disabled = true`) y usa **Entra ID + RBAC de datos** con identidades administradas: nada que rotar ni filtrar.
- **Red:** *Private Endpoint* y **acceso público desactivado** en producción; zona DNS privada enlazada a las redes que consumen.
- **Cifrado:** en reposo siempre (clave de Microsoft o **clave propia** en Key Vault); en tránsito TLS 1.2 como mínimo.
- **Mínimo privilegio:** *Data Reader* para consumidores de solo lectura; roles personalizados si necesitas permisos finos (por ejemplo, sin borrado).
- **Segmentación por inquilino:** clave `/tenantId` y filtro obligatorio en el repositorio (no confíes solo en la UI).
- **Datos sensibles:** no guardes secretos en documentos; usa cifrado a nivel de campo (*Always Encrypted* de Cosmos, *verifica su soporte en Java*) o tokenización.
- **Auditoría:** registros de diagnóstico a Log Analytics; alertas ante 401/403 inusuales; *Defender for Azure Cosmos DB* (verifica el nombre vigente).
- **Copias:** copia continua y pruebas de restauración; protección contra borrado con *locks* de recurso.

### IAM de este servicio

| Plano | Quién | Qué hace | Rol/permiso mínimo |
|---|---|---|---|
| **Control** (Azure RBAC) | Plataforma/IaC | Crear cuentas, bases y contenedores | *Contributor* acotado al grupo de recursos (o *DocumentDB Account Contributor*) |
| **Control** | Seguridad | Red, claves, diagnóstico | *Contributor* con alcance a la cuenta |
| **Control** | Observabilidad | Ver métricas y configuración | *Reader* y *Monitoring Reader* |
| **Datos** (Cosmos RBAC) | Aplicación que lee y escribe | CRUD en sus contenedores | *Cosmos DB Built-in Data Contributor* acotado a la base/contenedor |
| **Datos** | Aplicación de solo lectura | Consultas | *Cosmos DB Built-in Data Reader* |
| **Datos** | Procesador del change feed | Leer el feed y escribir arrendamientos | *Data Reader* en el contenedor fuente + *Data Contributor* en `leases` |
| **Datos** | Analistas | Consultas puntuales | *Data Reader* (mejor, sobre una réplica analítica/*mirror*) |

> El rol *Owner* o *Contributor* de Azure **no da acceso a los documentos**: los permisos de datos son roles de Cosmos (`az cosmosdb sql role assignment`).

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- **Elegir la clave de partición pensando en las consultas** y en el reparto de escrituras.
- Preferir **lecturas puntuales** (`id` + clave) a consultas.
- Incluir **la clave de partición en todas las consultas** frecuentes.
- **Excluir del índice** lo que no consultas; añadir índices compuestos para `ORDER BY`.
- **Autoscale** para cargas variables; alertas de *Normalized RU Consumption*.
- Un **cliente singleton**, modo directo, `preferredRegions`.
- **`id` determinista** para idempotencia; **ETag** en actualizaciones concurrentes; **patch** para cambios parciales.
- **Lote transaccional** para pedido + evento Outbox en la misma partición.
- Manejadores del change feed **idempotentes** y una cola de errores.
- Paginar con *continuation token*; limitar el tamaño de página.
- **Desactivar claves** y usar RBAC; *Private Endpoint*.
- Registrar `getRequestCharge()` y `getDiagnostics()` ante respuestas lentas.

**Qué NO hacer**
- Elegir una clave con pocos valores o que crezca sin fin en una sola partición (fecha, estado).
- Hacer `SELECT *` entre particiones sin filtro en rutas calientes.
- Crear un cliente por solicitud.
- Usar `OFFSET/LIMIT` grandes para paginar (cuestan cada vez más RU).
- Guardar documentos enormes o binarios (límite 2 MB; usa Blob).
- Esperar `JOIN`s entre contenedores o transacciones entre particiones.
- Confiar en las claves de la cuenta compartidas por todos.
- Leer el change feed sin idempotencia: se entrega al menos una vez.
- Ignorar los 429: significan que te quedas corto de RU o tienes una partición caliente.
- Poner `defaultTtl` sin pensar: borra datos de verdad.
- Cambiar de clave de partición "luego": implica migrar los datos a otro contenedor.
- Guardar dinero como decimal/`double` o fechas como números (el SDK serializa `Instant` como número si no lo configuras).

---

## 8. Límites, costos y versiones

| Límite (vigente a la fecha de redacción; *verifica la página de cuotas*) | Valor |
|---|---|
| Tamaño máximo de un documento | 2 MB |
| Almacenamiento por partición lógica | 20 GB |
| RU/s máximos por partición (lógica y física) | 10 000 |
| Mínimo por contenedor dedicado (manual / autoscale) | 400 RU/s / 1 000 RU/s máx. |
| RU/s máximos por contenedor o base (ampliable por soporte) | 1 000 000 |
| Operaciones por lote transaccional | 100 |
| Tamaño de solicitud / respuesta paginada | 2 MB / 4 MB |
| Duración de una operación (incluye una página de consulta) | 5 s |
| Longitud de una consulta | 512 KB |
| `JOIN`s por consulta | 10 |
| Claves únicas por contenedor | 10 |
| Bases + contenedores por cuenta | 500 |
| Capa gratuita | 1 000 RU/s + 25 GB, una por suscripción |

- **Costo:** RU/s aprovisionadas (o consumidas en serverless) × número de regiones, almacenamiento (GB), copia continua, escrituras multiregión. El mayor ahorro suele venir de **excluir índices**, **buenos modelos de partición** y **autoscale**. *Verifica precios y reservas de capacidad.*
- **Versiones:** SDK `azure-cosmos` **4.83.0** (administrado por el BOM de Azure SDK 1.3.9 de estos apuntes). **Spring Data Cosmos** (`azure-spring-data-cosmos`) es una librería aparte: *confirma en el mapa de versiones de Spring Cloud Azure si ya soporta Spring Boot 4 / Spring Data 4 antes de adoptarla.* Por eso aquí usamos el SDK directamente, que no depende de Spring.
- **Cambios frecuentes:** modos del change feed, búsqueda vectorial, mirroring y la capacidad de escritura multiregión evolucionan; confirma disponibilidad antes de diseñar.

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
