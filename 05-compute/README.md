# 05 · Compute: App Service, Function Apps y AKS

Dónde corre tu código. **Azure App Service**, **Azure Functions** y **AKS** (más **Container Apps** como punto medio), con sus equivalentes en **AWS**, **OCI** y **GCP**.

---

## 1. Qué es (con analogía)

Moverse por la ciudad:

| Opción de transporte | Servicio | Cuándo conviene |
|---|---|---|
| **Bus con ruta fija** (pagas el asiento aunque esté vacío) | **App Service** | Una aplicación web o API estable |
| **Taxi por viaje** (pagas solo cuando lo usas) | **Functions** (serverless) | Tareas cortas disparadas por eventos |
| **Servicio de mensajería con tu propio camión** | **Container Apps / Cloud Run / App Runner** | Contenedores sin administrar Kubernetes |
| **Flota propia con central de logística** | **AKS** (Kubernetes) | Muchos servicios, control fino, equipos de plataforma |
| **Alquilar un auto y manejarlo tú** | **Máquina virtual** | Software heredado o control total del SO |

> Regla: elige el nivel **más alto (más administrado)** que cubra tu necesidad. Cada paso hacia abajo te da control, pero también trabajo.

---

## 2. Para qué sirve y cuándo NO usarlo

| Servicio | Sirve para | NO lo uses si |
|---|---|---|
| App Service | Web apps y APIs (Java, .NET, Node, Python), slots de despliegue, escalado | Necesitas procesos de fondo muy específicos o control del SO |
| Functions | Reaccionar a eventos (cola, blob, timer, HTTP corto) | Procesos de horas o con estado en memoria |
| Container Apps | Microservicios en contenedores, escalado a cero, jobs | Necesitas APIs de Kubernetes directas |
| AKS | Plataforma con muchos servicios, mallas, operadores, control total | Tienes 1 o 2 apps simples: es sobreingeniería |
| VM | Software que no se puede contenerizar | Una app web normal |

---

## 3. Conceptos clave

| Término | Definición simple |
|---|---|
| **Plan (App Service plan)** | Las "máquinas" que alquilas; varias apps pueden compartirlo |
| **Slot** | Copia de la app (staging) para probar y luego intercambiar sin caída |
| **Trigger** | Lo que dispara una función (mensaje, archivo, hora, HTTP) |
| **Binding** | Conexión declarativa de entrada/salida de una función |
| **Cold start** | Demora de la primera ejecución cuando no había instancias activas |
| **Pod** | Unidad mínima en Kubernetes: uno o más contenedores |
| **Deployment** | Describe cuántas copias de un pod y cómo actualizarlas |
| **Service** | Nombre/IP estable para llegar a un grupo de pods |
| **HPA** | Escalado automático de pods según métrica |
| **Node pool** | Grupo de máquinas del clúster con el mismo tamaño |
| **Requests / limits** | CPU y memoria reservadas / máximas por contenedor |
| **Probe (liveness/readiness)** | Chequeo de salud del contenedor |

---

## 4. Árbol de decisión

```
¿Es código corto disparado por un evento?
   Sí → Functions (o Lambda / Cloud Run functions)
   No ↓
¿Es una web/API única o pocas, sin necesidad de Kubernetes?
   Sí → App Service (o Container Apps si ya tienes contenedor)
   No ↓
¿Muchos servicios, necesitas operadores, mallas, control fino de red/nodos?
   Sí → AKS (EKS / OKE / GKE)
   No ↓
¿Tienes un contenedor y no quieres administrar nada?
   Sí → Container Apps (App Runner / Cloud Run / Container Instances)
```

---

## 5. Equivalencias en las 4 nubes

| Necesidad | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| Web/API administrada | App Service | Elastic Beanstalk / App Runner | Container Instances / Compute | App Engine / Cloud Run |
| Contenedores sin Kubernetes | **Container Apps** | **App Runner** / ECS Fargate | **Container Instances** | **Cloud Run** |
| Funciones | Functions | Lambda | Functions | Cloud Run functions |
| Kubernetes | AKS | EKS | OKE | GKE (Standard / Autopilot) |
| Jobs por lotes | Container Apps jobs / Functions timer | AWS Batch / ECS tasks / EventBridge | Container Instances / Functions | Cloud Run jobs |
| Máquinas virtuales | Virtual Machines | EC2 | Compute | Compute Engine |
| Escalado de VMs | VM Scale Sets | Auto Scaling Groups | Instance Pools | Managed Instance Groups |
| Registro de imágenes | ACR | ECR | OCIR | Artifact Registry |

### Diferencias reales

- **Cloud Run** corre cualquier contenedor HTTP y escala a cero; **no es Kubernetes**. Es lo más parecido a Container Apps / App Runner.
- **Lambda** tiene límite de tiempo por ejecución; **Functions** (según plan) también, así que revisa el límite vigente.
- **GKE Autopilot** administra los nodos por ti y cobra por recursos de pod; en AKS existe un modo similar (*AKS Automatic*; verifica disponibilidad y alcance).
- **EKS** cobra el plano de control; en **AKS** el nivel gratuito no lo cobra (el nivel Standard añade SLA con costo).
- **OKE** ofrece nodos administrados y nodos virtuales; verifica diferencias de soporte.

---

## 6. App Service en detalle

### 6.1 Piezas

```
Plan (SKU + región)
  └─ App (código/contenedor)
       ├─ Slots (staging, prod)
       ├─ Configuración (app settings)
       ├─ Identidad administrada
       └─ Red (integración VNet de salida, Private Endpoint de entrada)
```

| Tema | Detalle |
|---|---|
| SKUs | Free/Basic (pruebas), Standard (slots, autoscale), Premium v3 (producción), Isolated v2 (aislamiento total) |
| Slots | Disponibles desde Standard; permiten *swap* sin caída |
| Escalado | Horizontal (más instancias) y reglas de autoescalado |
| Entrada privada | Private Endpoint (`privatelink.azurewebsites.net`) |
| Salida privada | **VNet integration** (subnet delegada a `Microsoft.Web/serverFarms`) |

> **VNet integration** controla las llamadas **salientes** de la app; el **Private Endpoint** controla el tráfico **entrante**. Son cosas distintas y a menudo se necesitan las dos.

### 6.2 CLI (Spring Boot en Java)

```bash
RG=rg-estudio-compute
az group create -n $RG -l eastus2

az appservice plan create -g $RG -n plan-modalima --is-linux --sku P0v3
az webapp create -g $RG -p plan-modalima -n app-modalima-api --runtime "JAVA:21-java21"

# Configuración y desplegar el JAR
az webapp config appsettings set -g $RG -n app-modalima-api --settings SPRING_PROFILES_ACTIVE=prod
az webapp deploy -g $RG -n app-modalima-api --src-path target/app.jar --type jar

# Identidad administrada
az webapp identity assign -g $RG -n app-modalima-api

# Slot de staging y swap
az webapp deployment slot create -g $RG -n app-modalima-api --slot staging
az webapp deployment slot swap   -g $RG -n app-modalima-api --slot staging --target-slot production
```

> Las cadenas de runtime y los flags cambian; confirma con `az webapp list-runtimes` y `--help`.

### 6.3 Buenas prácticas específicas

- Activa **Health check** (ruta `/actuator/health` en Spring Boot) para que la plataforma saque instancias enfermas.
- Usa **slots** y *swap*, no despliegues directo sobre producción.
- Guarda secretos como **referencias a Key Vault** (módulo 04).
- Configura **Always On** si la app no debe dormirse.
- Para contenedores propios, expón el puerto con `WEBSITES_PORT`.

---

## 7. Azure Functions en detalle

### 7.1 Piezas

| Concepto | Detalle |
|---|---|
| **Trigger** | HTTP, Timer, Queue / Service Bus, Blob, Event Grid, Event Hubs, Cosmos DB |
| **Binding** | Entrada/salida declarativa (leer un blob, escribir en una cola) |
| **Plan de alojamiento** | **Flex Consumption** (escala por función, soporta VNet), **Premium** (instancias precalentadas), **Dedicado** (App Service plan), **Consumption** clásico (verifica su estado vigente) |
| **Durable Functions** | Orquestaciones con estado (flujos largos) |
| **Almacenamiento** | Requiere una cuenta de storage; usa conexión por **identidad**, no por clave |

### 7.2 Ejemplo en Java: HTTP y cola

```java
public class Funciones {

    @FunctionName("hola")
    public HttpResponseMessage hola(
            @HttpTrigger(name = "req", methods = {HttpMethod.GET},
                         authLevel = AuthorizationLevel.FUNCTION)
            HttpRequestMessage<Optional<String>> request,
            final ExecutionContext ctx) {

        String nombre = request.getQueryParameters().getOrDefault("nombre", "mundo");
        return request.createResponseBuilder(HttpStatus.OK).body("Hola " + nombre).build();
    }

    @FunctionName("procesarPedido")
    public void procesarPedido(
            @ServiceBusQueueTrigger(name = "mensaje", queueName = "pedidos",
                                    connection = "SB_CONEXION") String mensaje,
            final ExecutionContext ctx) {
        ctx.getLogger().info("Pedido recibido: " + mensaje);
        // Debe ser idempotente: el mismo mensaje puede llegar más de una vez.
    }
}
```

Conexión por identidad (sin cadena de conexión), en los *app settings*:
```
SB_CONEXION__fullyQualifiedNamespace = sb-modalima.servicebus.windows.net
```
y el rol *Azure Service Bus Data Receiver* para la identidad de la función.

### 7.3 CLI

```bash
az storage account create -g $RG -n stfuncmodalima01 -l eastus2 --sku Standard_LRS

az functionapp create -g $RG -n func-modalima01 \
  --storage-account stfuncmodalima01 \
  --flexconsumption-location eastus2 \
  --runtime java --runtime-version 21
```

### 7.4 Reglas de oro para funciones

- **Idempotencia:** procesar el mismo mensaje dos veces no debe romper nada.
- **Funciones cortas:** si dura mucho, divídela o usa Durable Functions / un job.
- **Cold start:** mide; si te afecta, usa plan Premium o instancias siempre listas.
- **Una función, una responsabilidad.**
- **Reintentos y dead-letter:** define qué pasa con los mensajes que fallan siempre.

---

## 8. AKS en detalle

### 8.1 Arquitectura

```
Plano de control (administrado por Azure: API server, etcd, scheduler)
        │
 ┌──────┴──────────────────────────┐
 │ Node pool "system"  (CoreDNS…)  │
 │ Node pool "user"    (tus pods)  │
 └─────────────────────────────────┘
```

| Tema | Detalle |
|---|---|
| Niveles | Free, Standard (con SLA) y Premium: verifica diferencias |
| Node pools | `system` para componentes del clúster, `user` para tus aplicaciones; puedes separar por tamaño o por carga |
| Escalado | Cluster Autoscaler (nodos), HPA (pods), KEDA (por eventos: colas, streams) |
| Actualizaciones | Canales de auto-upgrade para Kubernetes y SO de nodos |
| Almacenamiento | Discos (Azure Disk) y archivos (Azure Files) con CSI |
| Observabilidad | Container Insights, Managed Prometheus/Grafana |
| Políticas | Azure Policy para Kubernetes (módulo 10) |
| Red e identidad | Módulos 01, 02 y 03 |

### 8.2 Crear un clúster de estudio

```bash
az aks create -g $RG -n aks-estudio \
  --node-count 2 --node-vm-size Standard_B2s \
  --network-plugin azure --network-plugin-mode overlay \
  --enable-managed-identity \
  --enable-oidc-issuer --enable-workload-identity \
  --generate-ssh-keys

az aks get-credentials -g $RG -n aks-estudio
kubectl get nodes

# Para ahorrar en el lab:
az aks stop  -g $RG -n aks-estudio
az aks start -g $RG -n aks-estudio
```

### 8.3 Un Deployment bien hecho

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: api-pedidos
  namespace: modalima
spec:
  replicas: 2
  selector:
    matchLabels: { app: api-pedidos }
  template:
    metadata:
      labels: { app: api-pedidos }
    spec:
      serviceAccountName: sa-api
      containers:
        - name: api
          image: acrmodalima.azurecr.io/api-pedidos:1.4.0
          ports: [{ containerPort: 8080 }]
          resources:
            requests: { cpu: "250m", memory: "512Mi" }
            limits:   { memory: "768Mi" }
          readinessProbe:
            httpGet: { path: /actuator/health/readiness, port: 8080 }
            initialDelaySeconds: 20
          livenessProbe:
            httpGet: { path: /actuator/health/liveness, port: 8080 }
            initialDelaySeconds: 40
---
apiVersion: v1
kind: Service
metadata:
  name: svc-pedidos
  namespace: modalima
spec:
  selector: { app: api-pedidos }
  ports: [{ port: 80, targetPort: 8080 }]
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: hpa-pedidos
  namespace: modalima
spec:
  scaleTargetRef: { apiVersion: apps/v1, kind: Deployment, name: api-pedidos }
  minReplicas: 2
  maxReplicas: 10
  metrics:
    - type: Resource
      resource:
        name: cpu
        target: { type: Utilization, averageUtilization: 70 }
```

### 8.4 Imagen de Java para contenedores

```dockerfile
FROM eclipse-temurin:21-jre
RUN useradd --system --uid 10001 app
WORKDIR /app
COPY target/app.jar app.jar
USER 10001
EXPOSE 8080
ENTRYPOINT ["java", "-XX:MaxRAMPercentage=75", "-jar", "app.jar"]
```
- `MaxRAMPercentage` hace que la JVM respete el límite de memoria del contenedor.
- Corre como usuario **no root**.
- Implementa *graceful shutdown* (`server.shutdown=graceful` en Spring Boot).

---

## 9. Casos de uso de vida real

### Caso 1 · El sitio de "ModaLima" en App Service
- **Problema:** servidor propio que se caía en campañas.
- **Solución:** App Service Premium con autoescalado entre 2 y 6 instancias, slot de staging y health check.
- **Resultado:** despliegues sin caída y campañas sin incidentes.
- **Lección:** un servicio PaaS simple resuelve el 80 % de las webs.

### Caso 2 · Miniaturas automáticas
- **Problema:** las fotos de producto subían en 8 MB y la tienda era lenta.
- **Solución:** una **función** disparada por "blob creado" genera 3 tamaños y los guarda en otro contenedor.
- **Resultado:** páginas más rápidas; costo casi nulo.
- **Lección:** tareas por evento = serverless.

### Caso 3 · Microservicios en AKS
- **Problema:** 15 servicios con ciclos de despliegue distintos y necesidad de escalar de forma independiente.
- **Solución:** AKS con pools `system` y `user`, HPA, KEDA para consumidores de cola, ingress interno y APIM delante.
- **Resultado:** despliegues independientes y escalado por servicio.
- **Lección:** AKS vale la pena cuando la **complejidad ya existe**; antes es un costo.

### Caso 4 · Reporte nocturno
- **Problema:** un proceso diario de 20 minutos corría en una VM encendida las 24 horas.
- **Solución:** un **job** programado (Container Apps job, o CronJob en AKS).
- **Lección:** si solo corre 20 minutos al día, no pagues 24 horas.

---

## 10. Qué hacer / qué NO hacer

**Qué hacer**
- Empezar por el servicio más administrado que sirva.
- Definir **requests y limits** y **probes** en todo contenedor.
- Usar **identidad administrada** y secretos desde Key Vault.
- Separar entornos y pools; **etiquetar** todo.
- Automatizar despliegues (IaC y pipeline) con slots o *rolling updates*.
- Apagar o escalar a cero lo que no se usa (dev, QA).
- Registrar métricas y logs desde el día uno.

**Qué NO hacer**
- Usar AKS para una sola aplicación pequeña.
- Correr contenedores como root o con imagen `latest`.
- Dejar sin límites de memoria (un pod puede tumbar un nodo).
- Poner estado importante dentro del contenedor o la instancia.
- Dejar funciones no idempotentes con reintentos activos.
- Desplegar directo a producción sin probar en staging.
- Dejar clústeres de prueba encendidos el fin de semana.

---

## 11. Troubleshooting

### App Service

| Síntoma | Causa probable | Solución |
|---|---|---|
| 503 / la app no arranca | Puerto incorrecto, arranque lento, falta de memoria | Ver *Log stream*; `WEBSITES_PORT`; aumentar tiempo de arranque o plan |
| 502 tras un *swap* | La app tarda en calentar | Usar *swap with preview* y *warm-up* |
| No llega a la base de datos privada | Falta integración VNet de salida o DNS privado | Integración VNet + zona DNS enlazada (módulo 02) |
| Referencia a Key Vault sin resolver | Identidad sin rol | Dar *Secrets User* |

### Functions

| Síntoma | Causa probable | Solución |
|---|---|---|
| No se dispara | Conexión del trigger mal definida o sin permiso | Revisar `connection` y roles de datos |
| Se ejecuta dos veces | Reintentos o *at-least-once* | Idempotencia |
| Lenta la primera llamada | Cold start | Plan con instancias precalentadas |
| Error de almacenamiento del host | Storage inaccesible o sin permiso | Acceso al storage por identidad y red |

### AKS

| Síntoma | Causa probable | Cómo comprobarlo |
|---|---|---|
| `CrashLoopBackOff` | La app falla al arrancar | `kubectl logs <pod> --previous` |
| `ImagePullBackOff` | ACR, DNS o permiso | `kubectl describe pod` y módulo 02 |
| `Pending` | Sin recursos o taints | `kubectl describe pod` → eventos |
| `OOMKilled` | Límite de memoria bajo | `kubectl describe pod` → *Last State* |
| El HPA no escala | Sin `requests` o sin métricas | `kubectl top pods`, `kubectl describe hpa` |
| Readiness falla | Ruta o puerto de la sonda errados | Probar la ruta con `curl` desde otro pod |

Comandos útiles:
```bash
kubectl get pods -n modalima -o wide
kubectl describe pod <pod> -n modalima
kubectl logs <pod> -n modalima --previous
kubectl get events -n modalima --sort-by=.lastTimestamp
kubectl rollout status deployment/api-pedidos -n modalima
kubectl rollout undo deployment/api-pedidos -n modalima
```

---

## 12. IAM del módulo

| Quién | Qué hace | Rol mínimo |
|---|---|---|
| Pipeline de despliegue | Desplegar a App Service | Website Contributor sobre la app o RG |
| Desarrollador | Ver logs y estado | Reader + Monitoring Reader |
| Equipo con `kubectl` | Obtener credenciales | Azure Kubernetes Service Cluster User Role + RBAC de Kubernetes |
| Administrador del clúster | Gestionar el clúster | Azure Kubernetes Service RBAC Cluster Admin |
| Nodos (kubelet) | Descargar imágenes | AcrPull |
| Función | Leer una cola | Azure Service Bus Data Receiver |

---

## 13. Repaso y entrevista

**Repaso**
1. ¿Qué diferencia hay entre VNet integration y Private Endpoint en App Service?
2. ¿Qué es el cold start y cómo se mitiga?
3. ¿Cuál es la diferencia entre `requests` y `limits`?
4. ¿Cuándo elegirías Container Apps en vez de AKS?
5. ¿Qué equivale a Container Apps en AWS, OCI y GCP?

**Entrevista**
- Una API en AKS responde lento solo en picos. ¿Qué revisas?
- ¿Cómo haces un despliegue sin caída en App Service y en AKS?
- ¿Cómo evitas que una función procese dos veces el mismo mensaje?
