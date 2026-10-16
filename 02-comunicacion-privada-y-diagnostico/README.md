# 02 · Comunicación privada entre servicios y diagnóstico

Este módulo responde dos preguntas:

1. **¿Cómo hago que mis servicios hablen entre sí sin salir a internet?** (la política y cómo se crea)
2. **¿Qué reviso cuando algo no conecta?** (AKS, APIM, bases de datos, storage)

Todo en **Azure**, con su equivalente en **AWS**, **OCI** y **GCP**.

---

## 1. La idea central

**Red privada** = el tráfico entre tus servicios nunca toca internet público.

**Analogía:** una oficina con pasillos internos. Para ir de contabilidad a sistemas, caminas por el pasillo. Salir a la calle y volver a entrar funciona, pero es más lento, más caro y menos seguro.

Para que **A hable con B en privado** deben cumplirse cinco cosas. Recuérdalas como **RPDSI**:

| Letra | Qué | Pregunta de control |
|---|---|---|
| **R** | **Ruta** | ¿Existe camino de red entre A y B? (misma red, peering, VPN, rutas) |
| **P** | **Permiso de red** | ¿NSG / firewall / política lo permiten en ese puerto? |
| **D** | **DNS** | ¿El nombre de B resuelve a su **IP privada** desde donde está A? |
| **S** | **Servicio** | ¿B tiene acceso privado habilitado y está escuchando en ese puerto? |
| **I** | **Identidad** | ¿A tiene permiso (rol, token, clave) para usar B? |

> El 80 % de los problemas "raros" son **D** (DNS). El siguiente grupo es **P** (reglas) y luego **I** (permisos disfrazados de problema de red).

---

## 2. La escalera de diagnóstico

Siempre en este orden. No saltes pasos.

```
0. ¿Qué cambió? (últimos despliegues, reglas, certificados, políticas)
        ↓
1. DNS        ¿el nombre resuelve? ¿a una IP privada?
        ↓
2. RUTA       ¿hay camino? (rutas efectivas, peering, next hop)
        ↓
3. FIREWALL   ¿NSG / firewall / política permite el puerto?
        ↓
4. PUERTO     ¿alguien escucha? (conexión TCP)
        ↓
5. TLS        ¿el certificado es válido y de confianza?
        ↓
6. IDENTIDAD  ¿el token / rol / clave tiene permiso? (401 / 403)
        ↓
7. APLICACIÓN ¿logs de la app? (404 / 500)
```

### Cómo leer el síntoma

| Lo que ves | Dónde está el problema | Significa |
|---|---|---|
| `Name or service not known`, `UnknownHostException` | **DNS** | El nombre no resuelve |
| Resuelve a **IP pública** cuando esperabas privada | **DNS / Private Endpoint** | Zona privada sin enlace o sin registro |
| **Timeout** (se queda esperando) | **Ruta o firewall** | Los paquetes se descartan en silencio |
| **Connection refused** | **Servicio / puerto** | Llegaste al destino, pero nadie escucha |
| Error de handshake / certificado | **TLS** | Certificado vencido, nombre que no coincide, CA no confiable |
| **401 / 403** | **Identidad** | La red está bien; falta permiso o token |
| **404 / 5xx** | **Aplicación** | La red está bien; falla la app o la ruta de API |

> **Un 403 no es un problema de red.** Si te responde algo, la red ya funcionó.

### Herramienta incluida

[`ConnCheck.java`](ConnCheck.java) prueba DNS y TCP en un solo paso e indica en qué escalón falla:

```bash
java ConnCheck.java mi-storage.blob.core.windows.net 443
java ConnCheck.java sql-modalima.database.windows.net 1433 5000
```

---

## 3. La política de comunicación

### 3.1 Matriz de ejemplo ("quién habla con quién")

| Origen → Destino | Puerto | Cómo queda privado en Azure |
|---|---|---|
| Internet → Application Gateway (WAF) | 443 | IP pública **solo** aquí |
| App Gateway → APIM | 443 | APIM en modo Internal (VNet) |
| APIM → servicios en AKS | 443 / 80 | Balanceador **interno** de AKS |
| AKS → Container Registry | 443 | Private Endpoint + zona `privatelink.azurecr.io` |
| AKS → Key Vault | 443 | Private Endpoint + identidad de carga de trabajo |
| App / Function → Azure SQL | 1433 | Private Endpoint |
| App / Function → PostgreSQL | 5432 | Private Endpoint o acceso por VNet |
| App / Function → Blob Storage | 443 | Private Endpoint |
| App → Service Bus | 443 / 5671 | Private Endpoint |
| App → Event Hubs (Kafka) | 9093 / 443 | Private Endpoint |
| On-premises ↔ Azure | varios | VPN o ExpressRoute |
| Admin → máquinas | 22 / 3389 | Bastion, nunca IP pública |

### 3.2 Equivalencias de "acceso privado a un servicio de la nube"

| Necesidad | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| Servicio administrado con IP privada en mi red | Private Endpoint | Interface VPC Endpoint (PrivateLink) | Private Endpoint | Private Service Connect |
| Acceso privado a storage / servicios de la nube | Service Endpoint | Gateway Endpoint (S3, DynamoDB) | Service Gateway | Private Google Access |
| Zona DNS para esos nombres | `privatelink.*` | Private DNS del endpoint (opción "Enable DNS name") | Private DNS | Zona privada de Cloud DNS |
| Salida a internet controlada | NAT Gateway | NAT Gateway | NAT Gateway | Cloud NAT |
| Exponer mi servicio de forma privada a otros | Private Link Service | Endpoint Service | Private Endpoint (servicio propio) | Servicio publicado con PSC |
| Bloquear acceso público del servicio | `public network access: Disabled` | Políticas de bucket/recurso + SCP | Reglas del recurso | VPC Service Controls / Org Policy |

### 3.3 Política recomendada (plantilla)

| ID | Regla |
|---|---|
| NET-01 | **Negar por defecto** entre subnets; permitir solo lo necesario. |
| NET-02 | Solo el punto de entrada (App Gateway / balanceador) tiene IP pública. |
| NET-03 | Servicios PaaS (SQL, Storage, Key Vault, Service Bus) con **Private Endpoint** y acceso público **deshabilitado**. |
| NET-04 | Cada Private Endpoint va con su **zona DNS privada enlazada** a todas las VNets que lo usan. |
| NET-05 | Aplicaciones usan **identidades administradas**, no claves en configuración. |
| NET-06 | Salida a internet **solo** por NAT Gateway o firewall, con lista de destinos permitidos. |
| NET-07 | Subnets dedicadas para AKS, APIM, App Gateway y Private Endpoints. |
| NET-08 | **Registros de flujo** activos y enviados a un workspace central. |
| NET-09 | Rangos IP registrados y **sin solapamiento** con on-premises. |
| NET-10 | Administración por Bastion / IAP / Session Manager; sin puertos 22/3389 abiertos a internet. |
| NET-11 | Cambios de red solo por **IaC** y revisión de código. |
| NET-12 | Las reglas anteriores se **imponen** con Azure Policy / SCP / Security Zones / Organization Policy. |

Ejemplos de políticas integradas de Azure que ayudan (busca los nombres exactos en *Azure Policy → Definitions*): "Network interfaces should not have public IPs", "Storage accounts should disable public network access", "Azure Key Vaults should use private link".

---

## 4. Cómo se crea: Private Endpoint + DNS privado (ejemplo con Storage)

```bash
RG=rg-estudio-net
VNET=vnet-estudio
ST=stmodalimaestudio01   # nombre único global, solo minúsculas y números

# 0) Subnet reservada para endpoints privados
az network vnet subnet create -g $RG --vnet-name $VNET -n snet-pe \
  --address-prefixes 10.10.9.0/27

# 1) Private Endpoint hacia el Blob del storage
STID=$(az storage account show -g $RG -n $ST --query id -o tsv)

az network private-endpoint create -g $RG -n pe-st-blob \
  --vnet-name $VNET --subnet snet-pe \
  --private-connection-resource-id $STID \
  --group-id blob --connection-name conn-st-blob

# 2) Zona DNS privada y enlace a la VNet
az network private-dns zone create -g $RG -n privatelink.blob.core.windows.net

az network private-dns link vnet create -g $RG -n link-$VNET \
  --zone-name privatelink.blob.core.windows.net \
  --virtual-network $VNET --registration-enabled false

# 3) Registrar la IP del endpoint en la zona
az network private-endpoint dns-zone-group create -g $RG \
  --endpoint-name pe-st-blob -n default \
  --private-dns-zone privatelink.blob.core.windows.net --zone-name blob

# 4) Cerrar el acceso público
az storage account update -g $RG -n $ST --public-network-access Disabled
```

**Verificación (desde una VM o pod dentro de la VNet):**

```bash
nslookup $ST.blob.core.windows.net
# Esperado: pasa por privatelink.blob.core.windows.net y responde 10.10.9.x
```

- Si responde una IP pública → falta el **enlace de la zona** a la VNet (o hay DNS personalizado sin reenvío).
- Si no resuelve → revisa el DNS de la VNet.

**Notas**
- Si tu VNet usa **DNS personalizado** (servidores propios), esos servidores deben reenviar las consultas de zonas privadas de Azure a `168.63.129.16` (DNS de la plataforma) o a un Private DNS Resolver.
- Por defecto el Private Endpoint no aplica NSG/UDR a su propia subnet; existe una opción de políticas de red de la subnet para habilitarlo. Verifica el comportamiento actual en la doc oficial.

---

## 5. AKS en red privada

### 5.1 Qué piezas intervienen

| Pieza | Para qué | Detalle |
|---|---|---|
| Subnet de nodos | Donde viven las VM del clúster | Con CNI clásico, **también** consume IP por pod |
| Plugin de red | Cómo obtienen IP los pods | Azure CNI (IP de la VNet), **Azure CNI Overlay** (pods en rango aparte, ahorra IP), kubenet (en proceso de retiro: verifica fecha) |
| Pod CIDR / Service CIDR | Rangos internos de Kubernetes | **No deben solaparse** con VNet, peerings ni on-premises |
| Clúster privado | El API server solo con IP privada | Se accede por VNet, VPN o `az aks command invoke` |
| Salida (outbound type) | Cómo salen los nodos a internet | `loadBalancer`, `managedNATGateway`, `userAssignedNATGateway` o `userDefinedRouting` (por firewall) |
| Balanceador interno | Exponer servicios solo a la VNet | Anotación en el `Service` |
| ACR | Registro de imágenes | Private Endpoint + permiso `AcrPull` |

### 5.2 Crear un clúster privado (estudio)

```bash
SUBNET_AKS_ID=$(az network vnet subnet show -g $RG --vnet-name $VNET -n snet-aks --query id -o tsv)

az aks create -g $RG -n aks-estudio \
  --enable-private-cluster \
  --network-plugin azure --network-plugin-mode overlay \
  --pod-cidr 192.168.0.0/16 \
  --service-cidr 172.16.0.0/16 --dns-service-ip 172.16.0.10 \
  --vnet-subnet-id $SUBNET_AKS_ID \
  --node-count 2 --generate-ssh-keys
```

> Los parámetros cambian entre versiones de CLI. Confirma con `az aks create --help`.

**Por qué esos rangos:** el `service-cidr` por defecto (`10.0.0.0/16`) choca con muchas redes on-premises; elegir uno propio evita el problema.

### 5.3 Exponer un servicio solo dentro de la VNet

```yaml
apiVersion: v1
kind: Service
metadata:
  name: api-interna
  annotations:
    service.beta.kubernetes.io/azure-load-balancer-internal: "true"
    service.beta.kubernetes.io/azure-load-balancer-internal-subnet: "snet-ilb"
spec:
  type: LoadBalancer
  selector:
    app: api
  ports:
    - port: 80
      targetPort: 8080
```

### 5.4 Entrar a un clúster privado sin estar en la VNet

```bash
az aks command invoke -g $RG -n aks-estudio --command "kubectl get nodes"
```

### 5.5 Pod de diagnóstico dentro del clúster

```bash
kubectl run netshoot --rm -it --image=nicolaka/netshoot -- bash
# Dentro:
nslookup stmodalimaestudio01.blob.core.windows.net
nc -zv sql-modalima.database.windows.net 1433
curl -vk https://api-interna.internal.modalima.example/health
```

---

## 6. APIM en red privada

### 6.1 Modos de red

| Modo | Quién ve el gateway | ¿Backend privado? | Cuándo |
|---|---|---|---|
| Sin red virtual | Internet | No (solo backends alcanzables públicamente) | Pruebas, APIs públicas |
| VNet **External** | Internet y la VNet | Sí | APIs públicas con backend privado |
| VNet **Internal** | Solo la VNet / on-premises | Sí | APIs internas, con App Gateway delante si hay que publicar |
| Private Endpoint (entrada) | Solo vía endpoint privado | Depende del tier | Cerrar la entrada |

> Los tiers (Developer, Basic, Standard, Premium y los v2) soportan **modos distintos**. Antes de diseñar, revisa la tabla actual de "networking options" en la doc oficial.

### 6.2 Arquitectura típica

```
Internet
   │
[ Application Gateway + WAF ]   ← única IP pública
   │ 443
[ APIM (modo Internal) ]        ← subnet dedicada
   │ 443
[ Balanceador interno de AKS ]  ← snet-ilb
   │
[ Pods ] ──(Private Endpoint)──► SQL / Key Vault / Storage
```

### 6.3 Requisitos de la subnet de APIM

- Subnet **dedicada** de APIM.
- NSG con reglas **entrantes** para el endpoint de administración (puerto 3443 desde la etiqueta `ApiManagement`) y para clientes (443); y reglas **salientes** hacia dependencias (Storage, Key Vault, Microsoft Entra ID, Azure Monitor, SQL según el tier).
- En modo Internal, **DNS** que resuelva el nombre del gateway (zona privada o servidor propio).

> Las dependencias exactas y los puertos cambian con el tiempo. Revisa la lista vigente en la doc de "virtual network configuration" de APIM.

---

## 7. Qué revisar cuando algo no funciona

### 7.1 Checklist de 10 minutos

1. **¿Qué cambió?** Mira el *Activity Log*, el último despliegue y los cambios de red/política.
2. **DNS:** `nslookup` desde el **mismo lugar** donde corre la app (pod, VM, función). ¿IP privada?
3. **Ruta:** rutas efectivas y siguiente salto de la NIC de origen.
4. **Firewall:** `IP flow verify` / NSG efectivo.
5. **Puerto:** `nc -zv host puerto` o `ConnCheck.java`.
6. **TLS:** `curl -v` o `openssl s_client -connect host:443 -servername host`.
7. **Identidad:** ¿el error es 401/403? Revisa roles y token.
8. **Servicio destino:** ¿acceso público deshabilitado y Private Endpoint **aprobado**?
9. **Capacidad:** IP libres en la subnet, SNAT, cuotas.
10. **Logs de la app** (última parada).

### 7.2 Comandos de Azure para el diagnóstico de red

```bash
# Rutas efectivas de la NIC de origen
az network nic show-effective-route-table -g $RG -n nic-vm-test -o table

# Reglas de NSG efectivas
az network nic list-effective-nsg -g $RG -n nic-vm-test

# ¿El tráfico está permitido?
az network watcher test-ip-flow -g $RG --vm vm-test \
  --direction Outbound --protocol TCP \
  --local 10.10.1.4:50000 --remote 10.10.2.4:1433

# Siguiente salto
az network watcher show-next-hop -g $RG --vm vm-test \
  --source-ip 10.10.1.4 --dest-ip 10.10.2.4
```

Además: **Connection Troubleshoot** de Network Watcher y los **VNet flow logs** (reemplazan a los NSG flow logs, que están en retiro; verifica fechas).

### 7.3 Escenarios de AKS

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `kubectl` da timeout desde mi laptop | Clúster privado, sin ruta o sin DNS hacia el API server | `nslookup` del nombre del API; ¿estoy en la VNet / VPN? | Jumpbox, VPN, enlazar la zona `privatelink.<región>.azmk8s.io`, o `az aks command invoke` |
| Nodos en `NotReady` o la creación falla | DNS personalizado que no reenvía, salida bloqueada, NSG | `kubectl describe node`, logs, probar resolución desde un nodo | Reenviar DNS a `168.63.129.16`, permitir salida requerida (etiqueta FQDN `AzureKubernetesService` si hay firewall) |
| Pods en `ImagePullBackOff` | ACR privado sin DNS/endpoint, falta `AcrPull`, salida a `mcr.microsoft.com` bloqueada | `kubectl describe pod` (mensaje del evento), `nslookup` del ACR desde un pod | Enlazar `privatelink.azurecr.io`, dar `AcrPull` a la identidad del kubelet, permitir salida |
| `Service` tipo LoadBalancer en `Pending` | Falta permiso sobre la subnet, sin IP libres, subnet mal indicada | `kubectl describe svc` → eventos | Dar *Network Contributor* sobre la subnet a la identidad del clúster, revisar anotaciones |
| Pods no resuelven nombres | CoreDNS con problemas, DNS de la VNet mal configurado | `kubectl get pods -n kube-system`, logs de CoreDNS | Corregir DNS / reenvío; reiniciar CoreDNS |
| Pod no llega a SQL/Key Vault | Nombre resuelve a IP pública o NSG del endpoint | `nslookup` en el pod; `nc -zv` | Enlazar zona DNS, revisar NSG y aprobación del endpoint |
| Pod llega pero recibe 403 | Identidad de carga de trabajo mal configurada | Logs de la app, rol asignado | Corregir federación/rol (no es de red) |
| "Subnet full" / no escalan los nodos | CNI clásico consume una IP por pod | IP disponibles en la subnet | Subnet mayor o Azure CNI Overlay |
| Alcanzo servicios de internet a veces y a veces no | Agotamiento de puertos SNAT | Métricas de SNAT del balanceador | NAT Gateway, más IP públicas, reutilizar conexiones |
| Pods no alcanzan hosts on-premises en `10.0.x.x` | Service CIDR por defecto solapado | `az aks show --query networkProfile` | Recrear con otro `service-cidr` |

### 7.4 Escenarios de APIM

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| **500** | Error en una política o en la expresión | Traza de la prueba en el portal | Corregir la política |
| **502** / `BackendConnectionFailure` | No conecta con el backend: DNS, ruta, firewall, TLS | Traza; resolver el backend **desde la subnet de APIM** | Revisar RPDSI desde APIM |
| **503** | Backend no disponible o sin instancias sanas | Estado del backend | Recuperar el backend |
| **504** | Timeout del backend | Tiempos de respuesta, política `forward-request` | Optimizar backend o aumentar el tiempo con criterio |
| **401 / 403** | Falta clave de suscripción, JWT inválido, IP no permitida | Cabeceras y política de validación | Corregir credenciales o política |
| **404** | Ruta o operación no coincide | Definición de la API | Ajustar `url template` o `backend url` |
| Backend privado inalcanzable | APIM **no está** en la VNet | Modo de red de APIM | Integrar APIM a la VNet o exponer el backend por Private Link |
| Error de certificado hacia el backend | Nombre del certificado distinto o CA no confiable | `openssl s_client` | Certificado correcto; **no** desactivar la validación en producción |
| El portal de APIM no abre en modo Internal | Falta DNS interno | `nslookup` del gateway | Zona privada con el registro del gateway |

> **Herramientas de APIM:** la pestaña **Test** con **Trace** del portal, y los registros del gateway en Application Insights / Log Analytics.

### 7.5 Peering, VPN y rutas

| Síntoma | Revisión |
|---|---|
| Funcionaba y dejó de funcionar | ¿Se eliminó un lado del peering? ¿Cambió una ruta o una regla? |
| Solo funciona en un sentido | Peering sin "allow forwarded traffic" / tránsito de gateway en el sentido que falta |
| Tráfico por firewall no regresa | **Ruteo asimétrico**: el retorno no pasa por el mismo firewall |
| Funciona con IP, no con nombre | DNS |

---

## 8. Equivalentes: qué revisar en AWS, OCI y GCP

### 8.1 Kubernetes privado

| Revisión | Azure (AKS) | AWS (EKS) | OCI (OKE) | GCP (GKE) |
|---|---|---|---|---|
| Acceso al API | Clúster privado + `command invoke` | Endpoint privado/público, grupos de seguridad | Endpoint privado en subnet propia (puerto 6443) | Clúster privado + redes autorizadas |
| Salida de nodos | NAT Gateway / firewall | NAT Gateway | NAT Gateway | Cloud NAT |
| Imágenes | ACR + Private Endpoint | ECR + endpoints `ecr.api`, `ecr.dkr` y S3 (gateway) | OCIR + Service Gateway | Artifact Registry + Private Google Access |
| IP para pods | CNI Overlay | VPC CNI (cuidado con agotar IP; existe delegación de prefijos) | Pod subnet (VCN-native) | Rangos secundarios (IP alias) |
| Permisos de red del clúster | Network Contributor en subnet | Roles IAM del clúster y nodos, entradas de acceso | Políticas de IAM de OKE | Cuentas de servicio y roles |
| Regla clásica olvidada | DNS personalizado sin reenvío | Falta de endpoints de VPC en clúster sin salida | Reglas de seguridad entre API (6443/12250) y nodos | Reglas de firewall del plano de control hacia nodos / webhooks |

**Qué revisar cuando no funciona**

- **EKS:** endpoints de VPC necesarios si no hay NAT (`ecr.api`, `ecr.dkr`, `s3`, `sts`, `logs`, `ec2`), grupos de seguridad entre plano de control y nodos, IP agotadas por el CNI.
- **OKE:** que existan reglas (security lists o NSG) entre la subnet del API, los nodos, el balanceador y los pods; que los nodos puedan salir por NAT o Service Gateway; políticas para que los nodos lean imágenes de OCIR.
- **GKE:** rango `/28` del plano de control, redes autorizadas, Cloud NAT para imágenes externas, Private Google Access para Google, firewall hacia webhooks de admisión, rangos secundarios con suficiente tamaño.

### 8.2 API Gateway privado

| Tema | Azure (APIM) | AWS (API Gateway) | OCI (API Gateway) | GCP |
|---|---|---|---|---|
| Entrada privada | Modo Internal / Private Endpoint | API **privada** + Interface Endpoint (`execute-api`) | Gateway en subnet privada | Gateway con acceso privado (PSC) o Apigee |
| Backend privado | APIM dentro de la VNet | **VPC Link** (NLB/ALB) | Subnet con ruta al backend | Serverless NEG / PSC |
| Control de acceso al endpoint | NSG, políticas | Política de recurso que permita el endpoint de VPC | Security List / NSG | Reglas de firewall / IAM |
| Qué se rompe con frecuencia | DNS interno, NSG de la subnet | Política de recurso sin permitir el endpoint, DNS privado sin habilitar | Reglas de seguridad | Permisos IAM del invocador |

### 8.3 Herramientas de diagnóstico de red

| Necesidad | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| ¿Hay camino? | Network Watcher (Connection Troubleshoot) | VPC Reachability Analyzer | Network Path Analyzer | Connectivity Tests |
| Registros de tráfico | VNet flow logs | VPC Flow Logs | VCN Flow Logs | VPC Flow Logs |
| Rutas efectivas | `show-effective-route-table` | `describe-route-tables` | Tabla de rutas de la subnet | `gcloud compute routes list` |
| Reglas efectivas | `list-effective-nsg` | Security Group / NACL | NSG + Security List | Reglas de firewall (logs) |
| Siguiente salto | `show-next-hop` | Reachability Analyzer | Network Path Analyzer | Connectivity Tests |

---

## 9. Casos de uso de vida real (detectives)

### Caso 1 · "Los pods no bajan la imagen"

- **Problema:** `ModaLima` movió su registro de imágenes a un ACR con Private Endpoint y cerró el acceso público. Los pods nuevos quedaron en `ImagePullBackOff`.
- **Pistas:** `kubectl describe pod` decía que no podía conectar con el registro. Desde un pod de diagnóstico, `nslookup` resolvía el ACR a una **IP pública**.
- **Causa:** la zona `privatelink.azurecr.io` no estaba enlazada a la VNet del clúster.
- **Solución:** crear el enlace de la zona a la VNet.
- **Lección:** DNS primero. El síntoma de "no conecta" estaba en el DNS.

### Caso 2 · "El API devuelve 504 solo en campaña"

- **Problema:** durante picos, algunas llamadas a un proveedor de pagos fallaban por timeout; el resto del día todo bien.
- **Pistas:** la métrica de **SNAT** del balanceador de salida mostraba puertos agotados; el resto de la red estaba sano.
- **Causa:** muchas conexiones nuevas desde pocos IP de salida; se acabaron los puertos disponibles.
- **Solución:** NAT Gateway con más IP públicas y reutilización de conexiones (pool de conexiones HTTP en la aplicación).
- **Lección:** los problemas de capacidad se ven como timeouts "intermitentes".

### Caso 3 · "Los pods no ven el sistema de inventario"

- **Problema:** una aplicación en AKS no podía llegar al servidor `10.0.5.20` de la sede central, aunque el VPN estaba arriba.
- **Pistas:** otras IP de la sede sí respondían.
- **Causa:** el `service-cidr` por defecto de AKS (`10.0.0.0/16`) **cubría** esa dirección; el clúster pensaba que era un servicio interno.
- **Solución:** recrear el clúster con un `service-cidr` que no se solape con ninguna red.
- **Lección:** planifica los rangos de Kubernetes igual que los de la VNet.

### Caso 4 · "No puedo hacer `kubectl` desde mi casa"

- **Problema:** tras crear un clúster privado, ningún desarrollador podía usar `kubectl`.
- **Causa:** el API server solo tenía IP privada.
- **Solución:** una VM de salto con Bastion para el equipo y `az aks command invoke` para tareas puntuales; más adelante, VPN con DNS correcto.
- **Lección:** privado significa **que debes planear cómo entras**.

---

## 10. IAM de este módulo

| Quién | Qué necesita | Rol mínimo (Azure) |
|---|---|---|
| Quien crea Private Endpoints | Permiso en la subnet y aprobación en el recurso destino | Network Contributor + permiso sobre el recurso |
| Identidad del clúster AKS | Crear balanceadores en la subnet | Network Contributor sobre la subnet |
| Kubelet (nodos) | Descargar imágenes | **AcrPull** sobre el registro |
| Aplicación que lee secretos | Obtener secretos | Key Vault Secrets User |
| Aplicación que lee blobs | Leer datos | Storage Blob Data Reader |
| Operadores del diagnóstico | Ver sin cambiar | Reader + Network Watcher Contributor |

Equivalentes: roles gestionados e IAM Policies en AWS, *policy statements* por compartimento en OCI, y roles IAM sobre proyecto/recurso en GCP (se detalla en el módulo 03).

---

## 11. Qué hacer / qué NO hacer

**Qué hacer**
- Seguir la escalera: DNS → ruta → firewall → puerto → TLS → identidad → aplicación.
- Probar **desde el mismo lugar** donde corre la aplicación.
- Dejar un **pod/VM de diagnóstico** con las herramientas listas.
- Registrar qué cambió con cada despliegue.
- Mantener un diagrama de rangos y zonas DNS.
- Usar IaC para que las reglas sean revisables.

**Qué NO hacer**
- Probar desde tu laptop y concluir que "la red está bien".
- Abrir el firewall "para ver si funciona" y olvidar cerrarlo.
- Desactivar la validación de certificados para "arreglar" un error TLS.
- Confundir 401/403 con problemas de red.
- Dejar `public network access` activo "por si acaso".
- Cambiar varias cosas a la vez: así no sabrás qué lo arregló.

---

## 12. Repaso y entrevista

**Repaso**
1. ¿Qué significan las letras de RPDSI?
2. Un nombre resuelve a IP pública pese a haber Private Endpoint: ¿qué revisas?
3. ¿Qué diferencia hay entre un timeout y un *connection refused*?
4. ¿Por qué el `service-cidr` por defecto de AKS puede causar problemas?
5. ¿Qué modo de red de APIM necesitas para llamar a un backend en una subnet privada?

**Entrevista**
- "Un pod no puede conectarse a la base de datos". ¿Qué haces, paso a paso?
- Diseña la red de una API con APIM, AKS y SQL, todo privado.
- ¿Cómo garantizas con políticas que nadie cree una base de datos con IP pública?
