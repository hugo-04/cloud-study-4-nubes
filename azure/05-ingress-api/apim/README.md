# Azure · Ingress y API · API Management (APIM)

## 1. Qué es

**API Management es la ventanilla única, con reglas, por la que tus APIs se ofrecen a quienes las consumen.** Se coloca *delante* de tus backends (AKS, App Service, Functions, lo que sea) y se encarga de lo que no quieres repetir en cada microservicio: **autenticar, limitar, transformar, versionar, documentar y medir**.

Analogía: **la ventanilla de atención a empresas de un banco**. Las empresas (consumidores) no entran a la bóveda (backend). En la ventanilla: les piden identificación (JWT/clave), anotan cuántos trámites hacen por minuto (límites y cuotas), traducen sus formularios (transformaciones), les entregan un manual (portal de desarrolladores) y le dicen al gerente cuánto se usa cada servicio (analítica).

Son **tres componentes**:

| Componente | Qué hace |
|---|---|
| **Gateway** (plano de datos) | Atiende el tráfico: ejecuta políticas y reenvía al backend. Administrado por Azure o **autoalojado** (contenedor en AKS/on‑premises) |
| **Plano de administración** | Donde defines APIs, productos, políticas (portal, CLI, ARM/Terraform, REST) |
| **Portal de desarrolladores** | Sitio de documentación y pruebas ("Try it") para los consumidores |

---

## 2. Cómo funciona por dentro

### 2.1 El flujo de una petición
```
Cliente
   │  HTTPS + (clave de suscripción) + (JWT)
   ▼
┌────────────────── APIM (gateway) ─────────────────────────┐
│ 1. Resuelve: host → API → operación (método + ruta)       │
│ 2. Comprueba suscripción (si la API la exige)             │
│ 3. INBOUND   → autenticar · limitar · validar · transformar│
│ 4. BACKEND   → reenviar (forward-request) con timeout     │
│ 5. OUTBOUND  → transformar la respuesta · cabeceras · caché│
│    ON-ERROR  → si algo falla en cualquier etapa            │
└───────────────────────────┬───────────────────────────────┘
                            ▼
                Backend (AKS / App Service / Functions)
```

### 2.2 Objetos (el modelo de datos)

| Objeto | Qué es | Notas |
|---|---|---|
| **API** | Conjunto de operaciones con una ruta base (`/pedidos`) | Se importa de **OpenAPI**, WSDL, Function App, App Service, Container App… |
| **Operación** | Método + plantilla de URL | `GET /pedidos/{id}` |
| **Producto** | Paquete de APIs con términos de uso | Puede exigir suscripción y aprobación; tiene sus propias políticas |
| **Suscripción** | Clave(s) que identifican a un consumidor | Ámbito: producto, API o todas las APIs. Dos claves (primaria/secundaria) para rotar |
| **Grupo / usuario** | Quién ve qué en el portal | Administradores, Desarrolladores, Invitados |
| **Política** | Regla XML que se ejecuta en la petición/respuesta | Ámbitos: global → producto → API → operación |
| **Fragmento de política** | Trozo de XML reutilizable | `<include-fragment fragment-id="..."/>` |
| **Named value** | Valor reutilizable (texto, secreto o **referencia a Key Vault**) | `{{valor}}` en políticas |
| **Backend** | Definición reutilizable del servicio destino | URL, credenciales, reintentos, *circuit breaker* |
| **Version set / versión** | Versiones públicas (v1, v2) | Esquemas por ruta, cabecera o query |
| **Revisión** | Cambio interno **no público** que luego se promueve | Permite probar sin afectar a la versión viva |
| **Logger / diagnóstico** | Envío de telemetría | Application Insights, Azure Monitor |
| **Certificados** | Para mTLS hacia el backend o validación | Desde Key Vault |
| **Gateway autoalojado** | El mismo gateway como contenedor propio | Tráfico local, híbrido |
| **Workspaces** | Gestión federada por equipos | Cada equipo administra sus APIs |

### 2.3 Niveles de servicio (tiers)

| Tier | Para qué | Red | Escala |
|---|---|---|---|
| **Consumption** | Serverless, pago por llamada, arranque rápido | Sin VNet completa | Automática |
| **Developer** | Pruebas (sin SLA) | VNet | 1 unidad |
| **Basic / Standard** | Producción pequeña/mediana | Limitada | Unidades |
| **Premium** | Producción exigente: multi-región, zonas, VNet completa | VNet interna/externa | Unidades por región |
| **v2** (Basic v2, Standard v2, Premium v2) | Nueva generación: aprovisionamiento rápido, integración con VNet más simple | VNet integration (salida), Private Endpoint (entrada) | Escala rápida |

*Las capacidades de cada tier (red, SLA, zonas, límites, precio) cambian con frecuencia: **verifica la tabla vigente**.* El tier Developer **no** es para producción.

### 2.4 El motor de políticas
Una política es un documento XML con cuatro secciones: `inbound`, `backend`, `outbound`, `on-error`.

- **Ámbitos y herencia:** se aplican en orden global → producto → API → operación. `<base />` dice *"aquí inserta lo del ámbito superior"*; si lo omites, pierdes la herencia.
- **Expresiones:** `@(...)` o `@{ ... }` en C# con el objeto `context` (`context.Request`, `context.Subscription`, `context.Variables`, `context.Response`).
- **Variables:** `<set-variable name="x" value="..."/>` para pasar datos entre secciones.

Políticas habituales:

| Familia | Políticas |
|---|---|
| **Autenticación** | `validate-jwt`, `validate-azure-ad-token`, `check-header`, `authentication-managed-identity`, `authentication-certificate`, `authentication-basic` |
| **Límites** | `rate-limit` (por suscripción), `rate-limit-by-key`, `quota`, `quota-by-key`, `ip-filter`, `limit-concurrency` |
| **Transformación** | `set-header`, `set-body`, `rewrite-uri`, `set-query-parameter`, `find-and-replace`, `xml-to-json`, `json-to-xml` |
| **Validación** | `validate-content`, `validate-parameters`, `validate-headers`, `validate-status-code` |
| **Flujo** | `choose` (if/else), `set-variable`, `return-response`, `mock-response`, `send-request`, `send-one-way-request`, `retry`, `wait`, `include-fragment` |
| **Backend** | `set-backend-service`, `forward-request` (timeout, seguir redirecciones), `retry` |
| **Caché** | `cache-lookup`, `cache-store`, `cache-lookup-value`, `cache-store-value` |
| **Navegador** | `cors`, `set-header` de seguridad |
| **Observabilidad** | `trace`, `log-to-eventhub`, `emit-metric` |
| **IA** | Políticas para pasarelas de modelos de lenguaje (límite de tokens, caché semántica…): *verifica el catálogo vigente* |

### 2.5 Autenticación: no confundir

| Mecanismo | Qué prueba | Seguridad real |
|---|---|---|
| **Clave de suscripción** (`Ocp-Apim-Subscription-Key`) | **Quién** (qué consumidor/producto) | Es un identificador de uso y facturación, **no** una autenticación fuerte |
| **JWT de Entra ID** (`validate-jwt`) | Identidad y permisos (audiencia, emisor, roles) | **Es la seguridad real** |
| **Certificado de cliente (mTLS)** | Identidad por certificado | Fuerte, para socios B2B |
| **Identidad administrada de APIM hacia el backend** | APIM es quien llama | Backend confía solo en APIM |

Patrón recomendado: **clave de suscripción + JWT** hacia APIM (medición y seguridad) y **JWT/identidad administrada de APIM** hacia el backend.

### 2.6 Versiones y revisiones
| Esquema | Ejemplo |
|---|---|
| Por ruta | `/v1/pedidos`, `/v2/pedidos` |
| Por cabecera | `Api-Version: 2` |
| Por query | `?api-version=2` |

**Versión** = contrato público (rompe compatibilidad → nueva versión). **Revisión** = ajuste interno compatible (se prueba y se promueve a "actual"). Regla: **no cambies una versión publicada**; añade otra y da un plazo de retiro.

### 2.7 Red

| Modo | Entrada (clientes → APIM) | Salida (APIM → backends) | Cuándo |
|---|---|---|---|
| **Público** (sin VNet) | Internet | Internet/backends públicos | Pruebas, backends públicos |
| **VNet externa** (inyección) | IP pública del gateway; backends en la VNet | VNet | Gateway público con backends privados |
| **VNet interna** (inyección) | **Solo** IP privada; delante un Application Gateway/Front Door | VNet | **Patrón empresarial**: APIM no expuesto |
| **Private Endpoint** (entrada) + integración VNet (salida) | Privada | VNet | Tiers v2/estándar según disponibilidad |
| **Gateway autoalojado** | Donde lo despliegues | Local | Backends en AKS u on‑premises |

Requisitos del modo VNet clásico (*verifica la lista vigente*):

| Dirección | Puerto | Origen/Destino (etiqueta) | Para qué |
|---|---|---|---|
| Entrada | 3443 | `ApiManagement` | Punto de administración (**obligatorio**) |
| Entrada | 6390 | `AzureLoadBalancer` | Sondas de infraestructura |
| Entrada | 80/443 | `Internet` (externa) o `VirtualNetwork` (interna) | Tráfico de clientes |
| Salida | 443 | `Storage`, `AzureActiveDirectory`, `AzureKeyVault`, `AzureMonitor`, `EventHub` | Dependencias del servicio |
| Salida | 1433 | `Sql` | Base de configuración |
| Salida | 6380/6381 u otros | según versión | Caché / sincronización |

- **Subred dedicada** (solo APIM) con NSG y rutas coherentes. Un UDR que fuerza todo por un firewall exige permitir esas dependencias.
- **DNS:** en modo interno debes crear tú los registros (`*.azure-api.net` → IP privada) en una zona privada.
- Diagnóstico de conectividad: [Diagnóstico](../../01-red/diagnostico-conectividad/README.md).

### 2.8 Observabilidad
| Herramienta | Uso |
|---|---|
| **Application Insights** | Trazas distribuidas, dependencias, fallos |
| **Registros de recurso** (`GatewayLogs`) | Cada petición: API, operación, código, tiempos, backend |
| **Rastreo** (`Ocp-Apim-Trace: true` + clave de suscripción) | Ver qué política se ejecutó (solo en pruebas; protégelo) |
| **Métricas** | Capacidad, solicitudes, latencia del gateway vs backend |
| **`emit-metric`** | Métricas personalizadas por dimensión |

### 2.9 Caché
- **Interna:** disponible en el servicio (varía por tier).
- **Externa (Redis):** cuando necesitas capacidad o compartirla entre regiones.
- Ideal para respuestas `GET` públicas estables; cuidado con datos por usuario (usa la clave de caché con `vary-by-header`, `vary-by-query-parameter`).

### 2.10 APIs como código (APIOps)
OpenAPI como contrato → importación automática → políticas en XML versionadas → promoción entre entornos (dev → test → prod) con pipelines. Terraform/Bicep para la infraestructura y herramientas de *extractor/publisher* para el contenido de APIM. [Ejemplos](ejemplos/).

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- **Exponer APIs a terceros** (socios, apps móviles) como *productos* con cuotas, claves y portal.
- **Centralizar la seguridad** de entrada (JWT, IPs, mTLS) y los límites.
- **Versionar** sin romper clientes.
- **Unificar** muchos microservicios bajo un dominio y un contrato.
- **Transformar** cabeceras, mapear rutas, mockear APIs mientras el backend no existe.
- **Medir** el uso por consumidor.

| NO lo uses si | Alternativa |
|---|---|
| Solo tienes 1–2 APIs internas y un solo equipo | Ingress / Application Gateway + JWT en la app |
| Esperas poner **lógica de negocio** en XML | Mantenla en servicios |
| Necesitas un WAF y TLS regional/global | [Application Gateway](../application-gateway/README.md) / [Front Door](../front-door-waf/README.md) delante |
| Comunicación servicio-a-servicio dentro del clúster | Service/malla; no pases por APIM (latencia y costo) |
| Mensajería asíncrona | [Service Bus / Event Hubs](../../07-mensajeria/) (APIM no es un broker) |
| Tráfico de ultra baja latencia y volumen enorme interno | Directo con mTLS de malla |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Producto** | Paquete de APIs + reglas de uso | "Socios Retail" |
| **Suscripción** | Clave de un consumidor a un producto | Distribuidor X |
| **Política** | Regla XML en entrada/salida | `rate-limit-by-key` |
| **`<base />`** | Hereda las políticas del ámbito superior | Imprescindible |
| **Named value** | Variable reutilizable | `{{tenant-id}}` |
| **Backend** | Destino reutilizable con sus propiedades | `backend-pedidos` |
| **Revisión** | Versión interna de pruebas | rev 2 |
| **Cuota vs límite de tasa** | Cuota: total en un periodo largo; tasa: calls por ventana corta | 10 000/mes vs 100/min |
| **Capacity metric** | % de carga del gateway | Alerta > 70 % |
| **Soft-delete** | Un APIM borrado queda retenido unos días | No puedes reusar el nombre |
| **Policy fragment** | Política reutilizable | Cabeceras de seguridad |

---

## 5. Cómo se usa

1. Crear el servicio (tier según el caso; Developer para estudiar; **tarda**).
2. Definir **backends** y **named values** (secretos en Key Vault).
3. Importar la API desde **OpenAPI**; ajustar la URL del servicio.
4. Escribir las **políticas** (JWT, límites, correlación, identidad hacia el backend).
5. Crear **productos** y **suscripciones**; asociar APIs.
6. Conectar **Application Insights** y los registros de recurso.
7. Publicar al portal de desarrolladores.
8. Ubicarlo en la red según el patrón (interno detrás de Application Gateway/Front Door).

Archivos de apoyo: [Terraform](ejemplos/terraform/main.tf) · [CLI](ejemplos/cli/apim.sh) · [políticas XML](ejemplos/xml/) · [OpenAPI de ejemplo](ejemplos/openapi/pedidos.json) · [KQL](ejemplos/kql/kql-apim.md).

### Comprobaciones rápidas
```bash
az apim show -g rg-estudio-apim -n apim-modalima-estudio --query "{estado:provisioningState, sku:sku.name, ip:publicIpAddresses}"
az apim api list -g rg-estudio-apim --service-name apim-modalima-estudio -o table
# Llamada con rastreo (solo pruebas)
curl -s -H "Ocp-Apim-Subscription-Key: <clave>" -H "Ocp-Apim-Trace: true" https://<gateway>/pedidos/42 -D -
```

---

## 6. Flujo de extremo a extremo (patrón empresarial)

```
Usuario
  │  HTTPS (api.modalima.example)
  ▼
DNS ──► Front Door / Application Gateway (WAF, TLS)      ← única IP pública
              │ HTTPS
              ▼
           APIM (modo Internal)                           ← JWT, límites, versiones
              │ HTTPS
              ▼
     Balanceador interno / Ingress de AKS
              │
              ▼
        Pods de la API ──(Private Endpoint)──► SQL / Key Vault / Storage
```

| Salto | Se valida |
|---|---|
| Usuario → entrada | Certificado, WAF, límites globales |
| Entrada → APIM | Host, ruta, certificado, regla de red |
| APIM → backend | Token (JWT / identidad administrada), límites, tiempo máximo |
| Backend → datos | Identidad administrada, red privada |

---

## 7. Seguridad
- **JWT obligatorio** (`validate-jwt` con emisor, audiencia y `roles`/`scp`); no basarse solo en la clave de suscripción.
- **El backend también valida el token** (defensa en profundidad) y solo acepta tráfico de APIM (red + identidad).
- **Named values secretos desde Key Vault** (con identidad administrada de APIM y rol *Key Vault Secrets User*).
- **No habilitar el rastreo** (`Ocp-Apim-Trace`) en producción abierto.
- **Cabeceras de seguridad** (`X-Content-Type-Options`, HSTS) y quitar `X-Powered-By`/`Server` en `outbound`.
- **Validación de contenido** contra el esquema (`validate-content`) para cortar basura temprano.
- **TLS 1.2+**; desactivar protocolos antiguos y cifrados débiles (propiedades del servicio).
- **Rotación** de claves de suscripción (primaria/secundaria) y expiración de suscripciones.
- **Portal de desarrolladores:** autenticación con Entra ID; revisa quién se registra.

### IAM de este servicio

| Quién | Qué hace | Rol mínimo |
|---|---|---|
| Equipo de APIs | Administrar APIs, productos y políticas | *API Management Service Contributor* (o *API Management Developer Portal Content Editor* para el portal) |
| Equipo de red | Subred, NSG, DNS | *Network Contributor* |
| Identidad administrada de APIM | Leer secretos de Key Vault; llamar al backend | *Key Vault Secrets User*; rol de aplicación del backend |
| Consumidor | Llamar a la API | Clave de suscripción + token con el rol/ámbito de la app |
| Auditoría | Ver configuración | *API Management Service Reader* / *Reader* |
| Pipeline (APIOps) | Publicar | *API Management Service Contributor* acotado al servicio |

---

## 8. Qué hacer y qué NO hacer

**Qué hacer**
- Validar **JWT** y aplicar **límites** en APIM, y *también* validar en el backend.
- Usar **identidad administrada** de APIM para llamar al backend; named values desde **Key Vault**.
- **OpenAPI como fuente de verdad**; versionar con *version sets*.
- Políticas **pequeñas, probadas y con `<base />`**; reutilizar con fragmentos.
- Devolver errores consistentes (RFC 7807, `application/problem+json`) desde `on-error`.
- Monitorear **capacidad**, latencia del gateway vs backend y 4xx/5xx por API.
- Poner timeouts explícitos (`forward-request`) y reintentos solo para operaciones idempotentes.
- Gestionar APIM **como código** y desplegar por entornos.
- Elegir el tier por requisitos de red/SLA, no por precio inicial.

**Qué NO hacer**
- Usar la clave de suscripción como **única** seguridad.
- Poner **lógica de negocio** o transformaciones gigantes en XML.
- Cambiar una versión publicada sin avisar.
- Usar **Developer** en producción.
- Dejar APIM **público** cuando el patrón pide interno detrás de un WAF.
- Olvidar `<base />` y perder políticas globales.
- Reintentar `POST` no idempotentes automáticamente.
- Pasar por APIM el tráfico interno servicio-a-servicio.
- Guardar secretos en texto plano en las políticas (usa named values secretos).

---

## 9. Límites, costos y versiones
- Costo: por **unidad** (Developer/Basic/Standard/Premium), por **llamada** (Consumption) y por **unidad v2**. Premium multi-región multiplica por región.
- Crear/actualizar un APIM clásico en VNet puede tardar **decenas de minutos**.
- Límites de operaciones, tamaño de política, tamaño de cuerpo, tiempo máximo, nº de APIs/productos: *verifica la página oficial de límites*.
- **Soft-delete:** tras borrar, el nombre queda reservado unos días; hay que **purgar** para reutilizarlo.
- Los tiers y la oferta v2 evolucionan: *verifica disponibilidad por región y la política de soporte*.

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
