# Azure · Compute · AKS (Azure Kubernetes Service)

## 1. Qué es

**AKS es Kubernetes administrado por Azure: Azure opera el "cerebro" del clúster (plano de control) y tú aportas las máquinas (nodos) donde corren tus contenedores.** Kubernetes decide *dónde* corre cada contenedor, los reinicia si fallan, los escala y los actualiza sin caída.

Analogía: una **flota propia con central de logística**. Tú pones los camiones (nodos) y la mercancía (tus contenedores); la central (plano de control, que Azure mantiene) reparte la carga, reemplaza camiones averiados y avisa cuándo falta flota.

| Quién administra | Qué |
|---|---|
| **Azure** | API server, etcd, scheduler, controladores (plano de control), parches del plano de control |
| **Tú** | Node pools (tamaño, cantidad, versión), tus manifiestos, redes, identidades, seguridad y observabilidad |

---

## 2. Cómo funciona por dentro

```
                kubectl / CI-CD / GitOps
                         │  HTTPS (Entra ID)
                         ▼
 ┌────────────── PLANO DE CONTROL (lo administra Azure) ──────────────┐
 │  API server ── etcd (estado) ── scheduler ── controller-manager    │
 └───────────────────────────────┬────────────────────────────────────┘
                                 │
        ┌────────────────────────┼─────────────────────────┐
        ▼                        ▼                         ▼
  Node pool "system"      Node pool "user-api"      Node pool "batch" (spot)
  (CoreDNS, metrics…)     (tus servicios)           (trabajos tolerantes a corte)
   nodo ─ kubelet          nodo ─ kubelet            nodo ─ kubelet
   ├ pod ─ contenedor      ├ pod ─ contenedor        └ pod ─ contenedor
   └ pod                   └ pod
```

### 2.1 Objetos de Kubernetes que usarás cada día

| Objeto | Qué es | Analogía |
|---|---|---|
| **Pod** | Unidad mínima: uno o más contenedores que comparten red y disco | Una camioneta con su carga |
| **Deployment** | Declara "quiero N copias de este pod" y cómo actualizarlas (*rolling update*) | La orden de reparto |
| **ReplicaSet** | Mantiene el número de pods (lo crea el Deployment) | El supervisor de turno |
| **Service** | Nombre e IP estables para llegar a un grupo de pods | Número de teléfono de una sucursal |
| **Ingress / Gateway** | Entrada HTTP(S) desde fuera del clúster | La recepción del edificio |
| **ConfigMap / Secret** | Configuración / datos sensibles inyectados al pod | La hoja de instrucciones |
| **Namespace** | Partición lógica (equipo, entorno) | Un piso del edificio |
| **StatefulSet** | Pods con identidad y disco propio estables | Un empleado con casillero fijo |
| **Job / CronJob** | Tarea que termina / programada | Un encargo / una ronda diaria |
| **HPA** | Escala pods por métrica | Contratar más repartidores |
| **PDB** | Mínimo de pods disponibles durante mantenimiento | "Nunca menos de 2 en turno" |
| **NetworkPolicy** | Quién puede hablar con quién | Reglas de las puertas internas |
| **ServiceAccount** | Identidad del pod dentro de Kubernetes | El carné del pod |

### 2.2 Node pools
- **System pool:** aloja componentes del clúster (CoreDNS, metrics-server). Mínimo 2–3 nodos en producción, con la *taint* `CriticalAddonsOnly=true:NoSchedule` para que no corran tus apps ahí.
- **User pools:** tus cargas. Puedes tener varios (CPU, memoria, GPU, **spot** para batch) y dirigirlos con `nodeSelector`, *taints/tolerations* y *affinity*.
- Cada pool es un **VM Scale Set**: misma imagen, mismo tamaño, escalable. Eliges **sistema operativo** (Azure Linux o Ubuntu), **zonas de disponibilidad** y **versión**.

### 2.3 Red del clúster (decisión importante, se toma al crear)

| Modelo | Cómo asigna IP a los pods | Cuándo |
|---|---|---|
| **Azure CNI Overlay** | Los pods usan un rango **overlay** privado; solo los nodos consumen IP de la VNet | **Recomendado por defecto**: escala sin agotar IPs |
| **Azure CNI (VNet / node subnet)** | Cada pod recibe una IP **de tu subred** | Pods deben ser alcanzables directamente desde la VNet o on-premises |
| **Azure CNI + Cilium** | Plano de datos eBPF (con overlay o VNet): políticas, observabilidad | Rendimiento y políticas L7/FQDN |
| **kubenet** | Esquema antiguo con tablas de rutas | **Heredado**: Microsoft anunció su retiro; *verifica la fecha* |

Rangos que **no deben solaparse** con tu VNet, otras VNets emparejadas ni on-premises: `service-cidr` (por defecto `10.0.0.0/16`), `pod-cidr` (overlay, por defecto `10.244.0.0/16`) y la IP del DNS del clúster (`10.0.0.10`).

**Tráfico saliente (`outboundType`):**

| Tipo | Cómo sale a Internet | Cuándo |
|---|---|---|
| `loadBalancer` | Por el balanceador estándar del clúster (SNAT) | Por defecto; cuidado con el agotamiento de puertos SNAT |
| `managedNATGateway` / `userAssignedNATGateway` | Por NAT Gateway | Muchas conexiones salientes, IP de salida fija ([NSG, rutas y NAT](../../01-red/nsg-rutas-nat/README.md)) |
| `userDefinedRouting` | Por tu firewall/NVA mediante UDR | Inspección o salida controlada |

**Acceso al API server:** público con *authorized IP ranges*, **clúster privado** (el API server solo con IP privada, vía Private Endpoint) o *API Server VNet Integration*. En empresas: clúster privado + acceso desde una red de administración.

**Servicios y DNS:** cada Service tiene un nombre `servicio.namespace.svc.cluster.local` resuelto por **CoreDNS**. Un Service `type: LoadBalancer` crea un balanceador de Azure; con la anotación `service.beta.kubernetes.io/azure-load-balancer-internal: "true"` es **interno** (IP privada de la VNet).

### 2.4 Identidad y acceso

| Quién | Cómo entra | Mecanismo |
|---|---|---|
| **Personas** (kubectl) | Entra ID | `--enable-aad --enable-azure-rbac` y `kubelogin`; sin cuentas locales (`--disable-local-accounts`) |
| **El clúster** (plano de control) | Identidad administrada del clúster | Crea balanceadores, discos, IPs |
| **Los nodos** (kubelet) | Identidad del kubelet | Descarga imágenes de ACR (`AcrPull`) |
| **Tus pods** hacia Azure | **Workload Identity** | OIDC issuer + credencial federada ([Workload Identity](../../02-iam/workload-identity/README.md)) |
| **Tus pods** hacia secretos | CSI Secrets Store | Montan secretos de Key Vault ([Key Vault](../../03-secretos/key-vault/README.md)) |

Roles de Azure típicos: *Azure Kubernetes Service Cluster User Role* (obtener credenciales), *Azure Kubernetes Service RBAC Reader / Writer / Admin / Cluster Admin* (permisos dentro de Kubernetes cuando usas Azure RBAC para Kubernetes).

### 2.5 Escalado: tres niveles que se complementan

| Nivel | Qué escala | Herramienta | Señal |
|---|---|---|---|
| Pods | Réplicas de un Deployment | **HPA** | CPU, memoria, métricas personalizadas |
| Pods por eventos | Réplicas (incluso a 0) | **KEDA** (add-on) | Cola de Service Bus, Event Hubs/Kafka lag, cron… |
| Nodos | Cantidad de VM del pool | **Cluster Autoscaler** (o provisión automática de nodos) | Pods en estado *Pending* por falta de recursos |

> Cadena típica: sube la carga → el HPA/KEDA pide más pods → no caben → el autoscaler añade nodos → los pods se programan. Cada eslabón tarda; planifica el margen.

### 2.6 Actualizaciones
- **Versión de Kubernetes:** Azure soporta unas pocas versiones menores a la vez (política N-2) con soporte extendido opcional (nivel Premium/LTS). *Verifica el calendario vigente.*
- **Canales de auto-upgrade:** `none`, `patch`, `stable`, `rapid`, `node-image`. Para el SO de los nodos: `NodeImage`, `SecurityPatch`, `Unmanaged`.
- **Cómo actualiza un pool:** crea nodos "extra" (*max surge*), **drena** un nodo (respetando los PDB), mueve los pods y borra el viejo. Si tus PDB son imposibles (`minAvailable` = réplicas), la actualización **se atasca**.
- **Ventanas de mantenimiento:** defines cuándo se permiten actualizaciones.

### 2.7 Almacenamiento
| Tipo | Controlador (CSI) | Modo | Notas |
|---|---|---|---|
| **Azure Disk** | `disk.csi.azure.com` | RWO (un nodo a la vez) | Anclado a una zona; usa clases con ZRS para tolerar zonas |
| **Azure Files** | `file.csi.azure.com` | RWX (varios pods) | NFS o SMB; más latencia |
| **Blob** | `blob.csi.azure.com` | RWX | Datos masivos, solo lectura habitual |

Regla: lo importante **no se guarda en el pod**; usa bases de datos y Storage externos. Reserva los volúmenes para casos que lo necesitan (StatefulSets).

### 2.8 Seguridad por capas
1. **Acceso al API:** Entra ID + RBAC, sin cuentas locales, clúster privado o IP autorizadas.
2. **Red:** NetworkPolicy por defecto *deny*, NSG/Firewall, Private Endpoints a los PaaS.
3. **Pods:** Pod Security (perfil *restricted*): no root, `readOnlyRootFilesystem`, sin privilegios, sin escalada.
4. **Imágenes:** de ACR (con Private Link), escaneadas, por *digest*, sin `latest`.
5. **Secretos:** CSI + Key Vault; sin secretos en Git.
6. **Políticas:** Azure Policy para Kubernetes (Gatekeeper) para imponer lo anterior ([Azure Policy](../../09-gobierno/azure-policy/README.md)).
7. **Detección:** Defender for Containers, logs de auditoría del API.

### 2.9 Observabilidad
- **Container Insights** (logs y métricas en Log Analytics) y **Managed Prometheus + Managed Grafana** (métricas de la aplicación con PodMonitor/ServiceMonitor).
- Eventos y logs de auditoría del plano de control mediante *diagnostic settings*.
- Trazas de aplicación: OpenTelemetry/Application Insights.

### 2.10 Modos de operación
- **AKS estándar:** tú gestionas pools, red y add-ons: máximo control.
- **AKS Automatic:** Azure aplica una configuración recomendada (autoscaling, upgrades, seguridad, red, observabilidad) y administra los nodos por ti: menos decisiones, menos control. *Verifica su disponibilidad y alcance.*

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- Muchos microservicios con ciclos de despliegue y escalado independientes.
- Cargas que necesitan control fino: mallas de servicio, operadores, GPUs, StatefulSets, políticas de red.
- Plataformas internas (equipos de plataforma que ofrecen un "paved road").
- Portabilidad de manifiestos (Kubernetes es el mismo en cualquier lugar).

| NO lo uses si | Alternativa |
|---|---|
| Tienes 1–3 aplicaciones simples | [App Service](../app-service/README.md) o [Container Apps](../container-apps/README.md) |
| Eventos cortos sin estado | [Function Apps](../function-apps/README.md) |
| Nadie en el equipo conoce Kubernetes y no hay quien lo opere | Container Apps |
| Solo necesitas escalar a cero cargas HTTP | Container Apps |
| Quieres "no pensar en infraestructura" | Servicios PaaS; o AKS Automatic si Kubernetes es obligatorio |

> Kubernetes es una **plataforma para construir plataformas**: da potencia pero exige operarla. Adóptalo cuando la complejidad ya existe.

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Nodo** | Máquina virtual que ejecuta pods | `aks-user-12345-vmss000001` |
| **Pod** | Unidad mínima de ejecución | `api-pedidos-7d9f…` |
| **Requests / limits** | Reservado / máximo de CPU y memoria | `requests: 250m / 512Mi` |
| **QoS** | Prioridad ante escasez (Guaranteed, Burstable, BestEffort) | requests = limits → Guaranteed |
| **Taint / toleration** | "No mezclar" / "yo sí puedo" | Pool de batch con taint |
| **Probe** | Chequeo de salud: *startup*, *readiness*, *liveness* | `/actuator/health/readiness` |
| **Drain** | Vaciar un nodo moviendo sus pods | Durante upgrades |
| **PDB** | Presupuesto de interrupciones | `minAvailable: 2` |
| **CNI** | Plugin que da red a los pods | Azure CNI Overlay |
| **CSI** | Plugin de almacenamiento | Azure Disk CSI |
| **Kubelet** | Agente de cada nodo | Lanza los contenedores |
| **GitOps** | El Git es la fuente de verdad del clúster | Flux |
| **Add-on** | Componente administrado por AKS | Key Vault CSI, KEDA |

---

## 5. Cómo se usa

### 5.1 Crear un clúster de estudio
```bash
az aks create -g rg-estudio-compute -n aks-estudio \
  --node-count 2 --node-vm-size Standard_B2s \
  --network-plugin azure --network-plugin-mode overlay \
  --enable-managed-identity \
  --enable-oidc-issuer --enable-workload-identity \
  --generate-ssh-keys
az aks get-credentials -g rg-estudio-compute -n aks-estudio
kubectl get nodes
az aks stop -g rg-estudio-compute -n aks-estudio       # ahorrar en el lab
```
Guion de producción (Entra ID, pools, ACR, KEDA, CSI, canales de upgrade): [ejemplos/cli/aks.sh](ejemplos/cli/aks.sh). Terraform: [ejemplos/terraform/main.tf](ejemplos/terraform/main.tf). Manifiestos listos: [ejemplos/yaml/](ejemplos/yaml/).

### 5.2 Un despliegue bien hecho
Los manifiestos de [ejemplos/yaml/10-deployment.yaml](ejemplos/yaml/10-deployment.yaml) incluyen lo que todo servicio Java debe tener: `requests/limits`, `startupProbe`/`readinessProbe`/`livenessProbe`, `preStop` + `terminationGracePeriodSeconds`, `securityContext` restrictivo, repartición entre zonas y no ejecutar como root.

### 5.3 Flujo de trabajo recomendado
1. **Construir** la imagen (Maven/Gradle → Jib o buildpacks) y subirla a ACR con una etiqueta inmutable.
2. **Declarar** el despliegue en Git (Helm o Kustomize).
3. **Aplicar** con GitOps (Flux/Argo CD) o desde el pipeline.
4. **Observar** el *rollout* (`kubectl rollout status`) y las métricas.
5. **Revertir** con `kubectl rollout undo` si falla.

### 5.4 Cómo comprobar que quedó bien
```bash
kubectl get nodes -o wide
kubectl get pods -A
kubectl get events -A --sort-by=.lastTimestamp | tail -20
kubectl auth can-i create deployments -n modalima
az aks show -g <rg> -n <aks> --query "{estado:powerState.code, version:kubernetesVersion, red:networkProfile.networkPlugin, oidc:oidcIssuerProfile.issuerUrl}" -o json
```

---

## 6. Seguridad

### IAM de este servicio

| Quién | Qué hace | Rol mínimo |
|---|---|---|
| Pipeline de despliegue | Obtener credenciales y aplicar | *Azure Kubernetes Service Cluster User Role* + *AKS RBAC Writer* en el namespace |
| Equipo de desarrollo | Ver/operar sus namespaces | *AKS RBAC Writer* (o Reader) en el namespace |
| Plataforma | Administrar el clúster | *AKS RBAC Cluster Admin* (con PIM) |
| Nodos (kubelet) | Descargar imágenes | *AcrPull* sobre el ACR |
| Pods | Hablar con Azure | Workload Identity + roles de datos mínimos |
| Creación del clúster | Crear recursos | *Contributor* sobre el grupo de recursos (y *Network Contributor* en la subred) |

### Checklist de endurecimiento
- [ ] Entra ID + Azure RBAC; **cuentas locales deshabilitadas**.
- [ ] Clúster privado o *authorized IP ranges*.
- [ ] NetworkPolicy *deny-all* por namespace + reglas explícitas.
- [ ] Pod Security *restricted*; imágenes solo desde tu ACR.
- [ ] Workload Identity; **cero** secretos de Azure en variables de entorno.
- [ ] Secretos con CSI + Key Vault.
- [ ] Azure Policy for Kubernetes activa.
- [ ] Defender for Containers y logs de auditoría hacia Log Analytics.
- [ ] Canal de auto-upgrade y ventana de mantenimiento definidos.

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- `requests` y `limits` de memoria en **todos** los contenedores; probes siempre.
- Tres zonas de disponibilidad, mínimo 2 réplicas y PDB razonable.
- Pools separados: `system` (con taint) y `user`; `spot` para batch.
- Etiquetas de imagen inmutables o *digest*; nunca `latest`.
- Un namespace por equipo/entorno con `ResourceQuota` y `LimitRange`.
- GitOps y la infraestructura del clúster en Terraform.
- Probar las actualizaciones primero en un clúster de preproducción.
- Apagar los clústeres de laboratorio.

**Qué NO hacer**
- Usar AKS para una sola aplicación pequeña.
- Correr como root o con `privileged`.
- Dejar el API server abierto a Internet sin restricciones.
- Poner `minAvailable` igual al número de réplicas (bloquea los upgrades).
- Poner límites de CPU muy bajos a aplicaciones JVM (throttling).
- Guardar estado importante dentro de los pods.
- Mezclar cargas críticas y de prueba en el mismo pool y namespace.
- Hacer `kubectl edit` en producción sin pasar por Git.

---

## 8. Límites, costos y versiones
- El plano de control en nivel **Free** no se cobra (sin SLA); **Standard** añade SLA con costo por clúster-hora; **Premium** añade soporte de largo plazo. Pagas **los nodos** (VM), discos, balanceadores e IPs.
- Límites de nodos por clúster, pods por nodo y tamaño del rango de IP dependen del modelo de red: *verifica "AKS quotas and limits"*.
- Las versiones de Kubernetes envejecen rápido (aprox. 4 meses por versión menor): planifica un ciclo de actualización.
- Add-ons y nombres de flags cambian entre versiones de la CLI: confirma con `az aks create --help`.
- En 2026 la comunidad retiró el controlador *ingress-nginx*; AKS recomienda migrar a **Gateway API** u otras opciones de entrada. Detalle y alternativas en [Ingress en AKS](../../05-ingress-api/ingress-aks/README.md) (*verifica el calendario de soporte*).

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
