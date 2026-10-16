# Azure · Compute · App Service

## 1. Qué es

**Azure App Service es un hosting administrado para aplicaciones web y APIs: tú entregas un JAR (o una imagen de contenedor) y Azure pone las máquinas, el balanceador, el HTTPS, los parches y la escala.** No administras sistema operativo ni servidor web.

Analogía: un **bus con ruta fija**. Alquilas asientos (el *plan*), pagas aunque vayan vacíos, y a cambio no te ocupas del motor, del combustible ni de la carretera.

| Tú te ocupas de | Azure se ocupa de |
|---|---|
| Tu código, su configuración y sus dependencias | Sistema operativo, parches, runtime de Java, certificados HTTPS, balanceo, reinicios |

---

## 2. Cómo funciona por dentro

```
Internet / Front Door / Application Gateway
        │  HTTPS 443  (App Service termina el TLS)
        ▼
┌─ Front ends (balanceador compartido de Azure) ───────────────┐
│  reparte peticiones entre las instancias del plan            │
└───────┬───────────────────────────┬──────────────────────────┘
        ▼                           ▼
  Worker (instancia 1)        Worker (instancia 2)      ← las "máquinas" del PLAN
  ┌─────────────────┐         ┌─────────────────┐
  │ App A  │ App B  │         │ App A  │ App B  │       varias apps comparten el plan
  └─────────────────┘         └─────────────────┘
        │ salida (opcional): VNet Integration → subred delegada → tu red privada
```

### 2.1 Plan y aplicación: dos recursos distintos
- **App Service Plan:** las máquinas. Define región, sistema operativo (Linux/Windows), **tamaño (SKU)** y **número de instancias**. Se factura el plan, no cada app.
- **App (Web App):** tu código. Vive dentro de un plan; varias apps pueden compartir el mismo.

| Familia de SKU | Para qué | Notas |
|---|---|---|
| Free / Shared | Probar | Sin SLA, sin Always On |
| **Basic** (B1–B3) | Desarrollo | Sin slots ni autoescalado |
| **Standard** (S1–S3) | Producción pequeña | Slots y autoescalado |
| **Premium v3** (P0v3…P3v3) | **Producción normal** | Más memoria por vCPU, zonas de disponibilidad, VNet |
| **Isolated v2** (App Service Environment) | Aislamiento total en tu VNet | Cuesta bastante más |

*Los nombres y tamaños cambian (hay generaciones nuevas): verifica en la documentación oficial.*

**Escalar** (cambiar tamaño del plan) = *scale up*. **Escalar** (más instancias) = *scale out*. Con autoescalado, las reglas añaden o quitan instancias según CPU, memoria o cola de peticiones.

### 2.2 Qué ocurre dentro de una instancia (Linux)
1. Azure descarga tu paquete o imagen y arranca el proceso (`java -jar`) o el contenedor.
2. Un **proxy interno** reenvía el tráfico al puerto de tu app. Con Java SE la plataforma indica el puerto en la variable `SERVER_PORT` (Spring Boot la lee sola); con tu propia imagen se define con `WEBSITES_PORT`.
3. Mientras la app no responda a la sonda de arranque, la instancia no recibe tráfico (hay un tiempo máximo de arranque configurable; si tu JVM tarda, súbelo).
4. El directorio `/home` es **almacenamiento persistente compartido** entre instancias; el resto del sistema de archivos es **efímero**.

### 2.3 Entrada de tráfico y sesiones
- Los **front ends** terminan el HTTPS y reenvían a tu app por HTTP, con las cabeceras `X-Forwarded-Proto`, `X-Forwarded-For` (incluye el puerto del cliente) y `X-Forwarded-Host`. Tu framework debe confiar en ellas (sección Java).
- **ARR affinity:** cookie que pega al cliente a una instancia. Con APIs sin estado, **desactívala**: así el reparto es parejo.
- Tiempo máximo de una petición HTTP en el front end: **del orden de 230 segundos**. Para trabajos largos, responde 202 y procesa aparte.

### 2.4 Slots de despliegue
```
 producción  ◄── swap ──►  staging
 (tráfico)               (nueva versión, ya calentada)
```
Un **slot** es una copia viva de la app con su propio nombre (`app-staging.azurewebsites.net`). Despliegas en `staging`, compruebas, y haces *swap*: Azure calienta el slot y cambia el enrutamiento **sin caída**. Los ajustes marcados como **slot settings** (pegajosos) no viajan con el swap (p. ej. cadenas de conexión de pruebas). También puedes enviar un **porcentaje** de tráfico al slot (pruebas en producción) y hacer *swap with preview*.

### 2.5 Configuración
- **App settings:** se exponen como **variables de entorno** del proceso. Spring Boot las convierte con su *relaxed binding* (`SPRING_DATASOURCE_URL` → `spring.datasource.url`).
- **Referencias a Key Vault:** `@Microsoft.KeyVault(SecretUri=...)` en un setting; la plataforma resuelve el secreto con la identidad de la app ([Key Vault](../../03-secretos/key-vault/README.md)).
- **Slot settings:** valores que se quedan en su slot.

### 2.6 Identidad
La app puede tener **Managed Identity** (system o user-assigned) para hablar con Key Vault, Storage, Service Bus y SQL sin secretos ([Managed Identity](../../02-iam/managed-identity/README.md)). También puede **descargar su imagen de ACR** con esa identidad (sin usuario/contraseña de administrador).

### 2.7 Red: entrada y salida son cosas distintas

| Dirección | Mecanismo | Qué hace |
|---|---|---|
| **Entrada** (quién me llama) | Access restrictions | Reglas por IP, service tag o subred (p. ej. solo Front Door) |
| **Entrada privada** | Private Endpoint (subrecurso `sites`) + zona `privatelink.azurewebsites.net` | La app deja de ser accesible desde Internet |
| **Salida** (a quién llamo) | **VNet Integration** regional | La app sale por una subred **delegada** a `Microsoft.Web/serverFarms` y alcanza recursos privados |

> **VNet Integration NO hace privada la entrada.** Es solo para las llamadas salientes. Muchas arquitecturas necesitan **las dos** cosas.

Con VNet Integration, el tráfico a Internet puede seguir saliendo por la ruta de la plataforma, o forzarse **todo** por la VNet (`vnetRouteAllEnabled`) para pasar por NAT Gateway o firewall ([NSG, rutas y NAT](../../01-red/nsg-rutas-nat/README.md)). La resolución DNS privada sigue las reglas de la VNet ([Private Endpoint y DNS](../../01-red/private-endpoint-dns/README.md)).

### 2.8 Salud y recuperación
- **Health check:** configuras una ruta (p. ej. `/actuator/health/readiness`). La plataforma la consulta cada minuto; si una instancia falla varias veces seguidas, **la saca del balanceador**; si sigue enferma, la reemplaza. Solo funciona con **2 o más instancias** para poder sacar una sin dejar la app sin servicio.
- **Always On:** evita que la app se descargue por inactividad (necesario para tareas en segundo plano y para evitar arranques fríos).
- **Auto-heal:** reglas que reinician el proceso por memoria, errores 5xx o lentitud.

### 2.9 Observabilidad
- **Log stream** y logs de aplicación (la salida estándar se captura).
- **Diagnostic settings** hacia Log Analytics (`AppServiceHTTPLogs`, `AppServiceConsoleLogs`, `AppServicePlatformLogs`).
- **Application Insights** con el agente de Java sin tocar el código (`ApplicationInsightsAgent_EXTENSION_VERSION=~3`).
- **Kudu / SCM** (`<app>.scm.azurewebsites.net`): consola, archivos y diagnóstico. Protégelo.

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para:** una o pocas APIs o webs HTTP, equipos pequeños, despliegues con slots, cargas de tráfico estable, quien no quiere administrar Kubernetes.

| NO lo uses si | Alternativa en Azure |
|---|---|
| Necesitas escalar a cero para ahorrar | [Container Apps](../container-apps/README.md) o [Functions](../function-apps/README.md) |
| Tienes decenas de microservicios con políticas de red, sidecars, mallas | [AKS](../aks/README.md) |
| La tarea responde a un evento y dura segundos | [Function Apps](../function-apps/README.md) |
| Necesitas control del sistema operativo o de procesos no HTTP | Máquina virtual |
| Procesos de fondo de horas con estado en memoria | Container Apps jobs o AKS |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Plan** | Las máquinas que alquilas | `plan-modalima` (P1v3, 2 instancias) |
| **Instancia / worker** | Una máquina del plan | 2 instancias = 2 copias de tu app |
| **Scale up / out** | Máquina más grande / más máquinas | P1v3→P2v3 / 2→4 |
| **Slot** | Copia de la app para probar antes de producción | `staging` |
| **Swap** | Intercambiar slots sin caída | staging ↔ production |
| **Slot setting** | Ajuste que no viaja con el swap | Cadena de conexión de pruebas |
| **Always On** | Mantener el proceso vivo | Imprescindible para jobs en segundo plano |
| **ARR affinity** | Cookie que pega al cliente a una instancia | Desactivar en APIs sin estado |
| **VNet Integration** | Salida de la app hacia tu red privada | Llegar a PostgreSQL privado |
| **Access restriction** | Regla de entrada por IP/subred/service tag | Solo Front Door |
| **Kudu (SCM)** | Sitio de administración de la app | Ver archivos y procesos |
| **Health check** | Ruta que la plataforma consulta para sacar instancias enfermas | `/actuator/health/readiness` |

---

## 5. Cómo se usa

### 5.1 Crear y desplegar (CLI)
```bash
az group create -n rg-estudio-compute -l eastus2
az appservice plan create -g rg-estudio-compute -n plan-modalima --is-linux --sku P0v3
az webapp create -g rg-estudio-compute -p plan-modalima -n app-modalima-api --runtime "JAVA:21-java21"
az webapp deploy -g rg-estudio-compute -n app-modalima-api --src-path target/app.jar --type jar
```
Guion completo (identidad, Key Vault, red, slots, autoescalado, contenedor desde ACR): [ejemplos/cli/app-service.sh](ejemplos/cli/app-service.sh). Terraform equivalente: [ejemplos/terraform/main.tf](ejemplos/terraform/main.tf).

> Las cadenas de runtime cambian: confirma con `az webapp list-runtimes --os linux`.

### 5.2 Formas de desplegar

| Forma | Cuándo |
|---|---|
| `az webapp deploy` / zip deploy | Pipeline simple con un JAR/WAR |
| GitHub Actions o Azure Pipelines | CI/CD normal (con identidad federada, sin secretos) |
| Imagen de contenedor desde ACR | Ya tienes Dockerfile; mismas imágenes que en otros entornos |
| Run from package | Despliegue atómico y de solo lectura |

### 5.3 Despliegue sin caída con slots
1. Despliega la nueva versión en `staging`.
2. Prueba `https://app-modalima-api-staging.azurewebsites.net/actuator/health`.
3. (Opcional) envía 10 % del tráfico al slot.
4. `swap` hacia producción. Si algo falla, **swap de vuelta** (rollback en segundos).

En Linux, para calentar durante el swap usa `WEBSITE_SWAP_WARMUP_PING_PATH` y `WEBSITE_SWAP_WARMUP_PING_STATUSES` (verifica en la doc oficial).

### 5.4 Cómo comprobar que quedó bien
```bash
az webapp show -g <rg> -n <app> --query "{estado:state, https:httpsOnly, id:identity.type}" -o json
curl -sS -o /dev/null -w "%{http_code}\n" https://<app>.azurewebsites.net/actuator/health
az webapp log tail -g <rg> -n <app>
```

---

## 6. Seguridad

| Tema | Qué hacer |
|---|---|
| **Identidad** | Managed Identity; cero cadenas con contraseña; referencias a Key Vault |
| **HTTPS** | `httpsOnly = true`, TLS mínimo 1.2, FTP deshabilitado (`ftpsState = Disabled`) |
| **Publicación** | Desactiva credenciales básicas de FTP y SCM (`basicPublishingCredentialsPolicies`); despliega con Entra ID |
| **Entrada** | Access restrictions (p. ej. solo Front Door con su `X-Azure-FDID`) o Private Endpoint |
| **Salida** | VNet Integration + rutas por NAT/Firewall; DNS privado para PaaS |
| **Autenticación de usuarios** | *Easy Auth* (autenticación integrada con Entra ID) delante de la app, o Spring Security / Quarkus OIDC dentro |
| **Depuración remota** | Apagada |
| **Imágenes** | De ACR con identidad (`AcrPull`), nunca con usuario administrador |

### IAM de este servicio

| Quién | Qué hace | Rol mínimo |
|---|---|---|
| Pipeline de despliegue | Publicar la app | *Website Contributor* sobre la app |
| Desarrollador | Ver estado y logs | *Reader* + *Monitoring Reader* |
| La app | Leer secretos / datos | Roles **de datos** a su identidad (Key Vault, Storage, Service Bus) |
| Plan de plataforma | Crear plan y app | *Contributor* sobre el grupo de recursos |

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- Dos o más instancias en producción (zonas si el SKU lo permite) y **health check**.
- **Slots** y *swap*; nunca desplegar directo a producción.
- Mantener la app **sin estado**: sesiones en Redis/base de datos, archivos en Blob.
- Desactivar ARR affinity en APIs sin estado.
- Confiar en las cabeceras `X-Forwarded-*` en el framework.
- Autoescalado con un mínimo ≥ 2 y un máximo con tope de costo.
- Poner **Always On** si hay procesos en segundo plano.
- Application Insights y alertas por 5xx y latencia.

**Qué NO hacer**
- Guardar archivos en el disco local esperando que persistan (solo `/home`, y compartido).
- Dejar el plan sobredimensionado "por si acaso" (se paga por hora).
- Usar `@Scheduled` sin pensar en que corre en **cada** instancia.
- Dejar abierto el sitio SCM/Kudu o FTP.
- Confundir VNet Integration con Private Endpoint.
- Meter 20 apps no relacionadas en un plan (se pelean por memoria y un reinicio las afecta a todas).
- Ignorar el tiempo de arranque de la JVM (la plataforma puede reiniciar una app que "no arranca").

---

## 8. Límites, costos y versiones

- Se factura **el plan** por hora de instancia, aunque no haya tráfico (los planes Free/Shared tienen reglas propias).
- Número máximo de slots, instancias y apps por plan dependen del SKU: *verifica "App Service limits"*.
- Tiempo máximo de petición ~230 s; tamaño de carga y conexiones simultáneas tienen límites.
- Versiones de Java disponibles (Java 17, 21, …) y de servidor (Tomcat, JBoss EAP) cambian: `az webapp list-runtimes`.
- Los nombres `*.azurewebsites.net` son únicos globalmente.

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
