# Azure · Ingress y API · Ingress en AKS

## 1. Qué es

**El *ingress* es la puerta por la que el tráfico HTTP(S) de afuera llega a los servicios que corren dentro del clúster de AKS.** En lugar de crear un balanceador de Azure por cada servicio, pones **una sola entrada** que mira el *host* (`api.modalima.example`) y la *ruta* (`/pedidos`) y reparte al Service correcto.

Analogía: el **recepcionista de un edificio**. Un solo mostrador atiende a todos y dice: "¿ventas? piso 2. ¿soporte? piso 3". Sin él, cada oficina tendría su propia puerta a la calle.

| Pieza | Papel |
|---|---|
| **Service tipo `LoadBalancer`** | Una puerta a la calle por servicio (L4, una IP y un balanceador cada uno) |
| **Ingress** (API clásica) | Reglas de host/ruta que un *controlador* convierte en configuración real |
| **Gateway API** (sucesora de Ingress) | Modelo más expresivo y con roles: `GatewayClass`, `Gateway`, `HTTPRoute` |
| **Controlador** | El software que implementa las reglas (NGINX, Application Gateway for Containers, Istio, Envoy…) |

---

## 2. Cómo funciona por dentro

```
Cliente ── HTTPS ──► DNS (api.modalima.example)
                      │
              IP del controlador (pública o INTERNA)
                      │  Service type=LoadBalancer  (Azure Load Balancer, L4)
                      ▼
          ┌──── Controlador de entrada (pods en el clúster) ────┐
          │  termina TLS · aplica reglas host/ruta · reescribe   │
          └───────────────┬───────────────────┬─────────────────┘
                          ▼                   ▼
                  Service svc-pedidos   Service svc-catalogo
                          ▼                   ▼
                       Pods                 Pods
```

### 2.1 Ingress vs Gateway API

| | **Ingress** | **Gateway API** |
|---|---|---|
| Objetos | `Ingress`, `IngressClass` | `GatewayClass`, `Gateway`, `HTTPRoute`, `GRPCRoute`, `ReferenceGrant` |
| Expresividad | Básica; lo demás va en **anotaciones** de cada controlador | Reparto por pesos, cabeceras, redirecciones, reescrituras, espejo de tráfico **en la propia API** |
| Roles | Un objeto lo mezcla todo | Plataforma define `Gateway`; cada equipo define sus `HTTPRoute` |
| Futuro | Estable, congelada | **Es la dirección del ecosistema** |

> Aprende los dos: Ingress para leer lo que ya existe; Gateway API para lo nuevo.

### 2.2 Opciones de controlador en Azure

| Opción | Qué es | Cuándo |
|---|---|---|
| **Application routing add-on** | Ingress administrado por AKS (NGINX por debajo) con integración a Key Vault y Azure DNS | Quieres algo sencillo y administrado. *Verifica el calendario: el proyecto ingress-nginx de la comunidad se retiró en 2026* |
| **Application Gateway for Containers (AGC)** | Balanceador L7 **fuera** del clúster, gestionado por Azure, con soporte de **Gateway API** e Ingress | **Recomendado para nuevos proyectos** en Azure: sin pods de proxy que operar, WAF, pesos de tráfico, mTLS |
| **AGIC** (Application Gateway Ingress Controller) | Controlador que programa un Application Gateway clásico | Ya tienes Application Gateway y quieres reutilizarlo |
| **Add-on de malla Istio** (ingress gateway) | Entrada de una malla de servicios | Ya usas malla y mTLS entre servicios |
| **Otros** (Traefik, Contour, Envoy Gateway, Kong, NGINX de F5) | Controladores de terceros | Requisitos específicos |

### 2.3 Entrada pública o interna
- **Pública:** el controlador (o el recurso fuera del clúster) tiene IP pública. Solo para entradas reales de Internet y siempre con WAF.
- **Interna:** `Service` con la anotación `service.beta.kubernetes.io/azure-load-balancer-internal: "true"` (IP privada de la VNet) y delante APIM, Application Gateway o Front Door con Private Link.

Anotaciones útiles del balanceador de Azure:

| Anotación | Efecto |
|---|---|
| `azure-load-balancer-internal: "true"` | Balanceador interno |
| `azure-load-balancer-internal-subnet: <subred>` | Subred donde nace la IP interna |
| `azure-load-balancer-ipv4: <ip>` | IP fija |
| `azure-load-balancer-health-probe-request-path: /healthz` | Ruta de la sonda del balanceador (necesaria con NGINX) |
| `azure-load-balancer-tcp-idle-timeout: "30"` | Minutos de inactividad antes de cortar (por defecto ~4) |
| `externalTrafficPolicy: Local` (campo del Service) | Conserva la **IP real del cliente** y evita un salto extra |

### 2.4 TLS y certificados
| Forma | Cómo |
|---|---|
| **cert-manager + Let's Encrypt** | Emite y renueva certificados automáticamente (desafío HTTP-01 o DNS-01 con Azure DNS y Workload Identity) |
| **Key Vault** | El certificado vive en el vault; el add-on o el CSI Secrets Store lo entrega al controlador |
| **Terminación en un balanceador externo** | Application Gateway / Front Door terminan el TLS; hacia el clúster va HTTP o HTTPS interno |

### 2.5 Qué ve tu aplicación Java
El controlador **termina el TLS** y reenvía por HTTP con `X-Forwarded-For`, `X-Forwarded-Proto`, `X-Forwarded-Host` y, si reescribe rutas, `X-Forwarded-Prefix`. Sin configurar el framework, tu app generará enlaces `http://` y redirecciones incorrectas.

### 2.6 Tiempos y tamaños
| Elemento | Valor típico | Qué rompe |
|---|---|---|
| Inactividad del Load Balancer de Azure | ~4 minutos | Conexiones largas (SSE, WebSocket) sin *heartbeat* |
| Lectura del proxy NGINX | 60 s | Respuestas largas → 504 |
| Tamaño de cuerpo NGINX | 1 MB | Subidas de archivos → 413 |

Los valores se ajustan por anotación o configuración del controlador. *Verifica los valores por defecto de tu controlador.*

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- Publicar varios servicios HTTP del clúster detrás de una sola IP/dominio.
- Terminar TLS y redirigir `http` → `https`.
- Enrutar por host y ruta; reescrituras; despliegues *canary* por pesos (Gateway API).
- Centralizar WAF y límites en la entrada.

| NO lo uses si | Alternativa |
|---|---|
| Solo expones TCP/UDP no HTTP | Service `LoadBalancer` (L4) |
| Necesitas autenticación, cuotas, versiones y portal para consumidores externos | **APIM** delante ([APIM](../apim/README.md)) |
| La entrada es global con CDN y failover entre regiones | [Front Door](../front-door-waf/README.md) delante |
| El tráfico es solo entre servicios del clúster | `Service` interno / malla |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **IngressClass** | Qué controlador atiende este Ingress | `webapprouting.kubernetes.azure.com` |
| **pathType** | Cómo se compara la ruta: `Exact`, `Prefix` | `/pedidos` + `Prefix` |
| **HTTPRoute** | Regla de enrutamiento de Gateway API | `/pedidos` → `svc-pedidos` |
| **Gateway** | Listener(s) de entrada (puerto, host, TLS) | Puerto 443, `*.modalima.example` |
| **backendRefs con peso** | Reparto del tráfico entre versiones | 90 % v1, 10 % v2 |
| **ExternalTrafficPolicy** | Cómo se enruta tráfico externo a los pods | `Local` conserva la IP del cliente |
| **cert-manager** | Operador que emite y renueva certificados | `ClusterIssuer` Let's Encrypt |
| **Rewrite** | Cambiar la ruta antes de llegar al backend | `/api/pedidos` → `/pedidos` |
| **Default backend** | A dónde va lo que no coincide con ninguna regla | Página 404 |

---

## 5. Cómo se usa

### 5.1 Application routing add-on (rápido)
```bash
az aks approuting enable -g rg-estudio-aks -n aks-modalima
kubectl get ingressclass          # webapprouting.kubernetes.azure.com
kubectl apply -f ejemplos/yaml/10-ingress-approuting.yaml
```
Para un certificado de Key Vault y DNS: `az aks approuting update --enable-kv --attach-kv <kvId>` y `az aks approuting zone add`.

### 5.2 Application Gateway for Containers + Gateway API
1. Crear el recurso AGC, un *frontend* y la **asociación** a una subred delegada a `Microsoft.ServiceNetworking/trafficControllers`.
2. Instalar el **ALB Controller** en el clúster (Helm) con Workload Identity.
3. Crear un `Gateway` y los `HTTPRoute` ([ejemplos/yaml/20-gateway-api-agc.yaml](ejemplos/yaml/20-gateway-api-agc.yaml)).

Pasos y comandos: [ejemplos/cli/ingress-aks.sh](ejemplos/cli/ingress-aks.sh). Recursos con Terraform: [ejemplos/terraform/main.tf](ejemplos/terraform/main.tf).

### 5.3 Ingress con TLS automático (cert-manager)
[ejemplos/yaml/30-cert-manager.yaml](ejemplos/yaml/30-cert-manager.yaml): `ClusterIssuer` de Let's Encrypt (staging y producción) y un `Ingress` con la anotación `cert-manager.io/cluster-issuer`.

### 5.4 Cómo comprobar que quedó bien
```bash
kubectl get ingress -A
kubectl describe ingress api-pedidos -n modalima              # Events: errores del controlador
kubectl get endpoints svc-pedidos -n modalima                 # ¿hay pods detrás?
kubectl -n app-routing-system logs deploy/nginx               # logs del add-on (si lo usas)
curl -vk --resolve api.modalima.example:443:<IP> https://api.modalima.example/pedidos/health
```

---

## 6. Seguridad
- **WAF** delante de toda entrada pública (Front Door, Application Gateway o AGC con política WAF).
- **TLS 1.2+**; redirección forzada a HTTPS; HSTS en la aplicación o el controlador.
- **No exponer** Services internos: por defecto `ClusterIP`; solo el controlador tiene `LoadBalancer`.
- **NetworkPolicy** que solo permita al namespace del controlador llegar a las apps ([AKS · YAML](../../04-compute/aks/ejemplos/yaml/30-networkpolicy.yaml)).
- **Cuotas:** `services.loadbalancers: 0` en el `ResourceQuota` de los namespaces de aplicaciones.
- **Límites de tamaño y de tasa** en la entrada para frenar abusos.
- **Cabeceras de seguridad** y ocultar versiones del servidor.

### IAM de este servicio

| Quién | Qué hace | Rol mínimo |
|---|---|---|
| Identidad del ALB Controller (AGC) | Programar el recurso AGC | *AppGw for Containers Configuration Manager* en el recurso y *Network Contributor* en la subred |
| Add-on de routing | Leer certificados | *Key Vault Secrets User* / *Certificates User* sobre el vault |
| cert-manager (DNS-01) | Crear registros TXT | *DNS Zone Contributor* sobre la zona |
| Equipo de plataforma | Administrar `Gateway`/`IngressClass` | RBAC de Kubernetes en el namespace de plataforma |
| Equipos de app | Crear `HTTPRoute`/`Ingress` | RBAC de Kubernetes en su namespace |

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- Una **sola** entrada para muchos servicios; `ClusterIP` para el resto.
- Preferir **Gateway API** (y AGC) en proyectos nuevos.
- `readinessProbe` correctas: el controlador solo envía tráfico a pods *Ready*.
- Configurar `forward-headers` en la aplicación.
- Subir los tiempos y tamaños de la entrada **solo** para las rutas que lo necesitan.
- `heartbeat` en conexiones largas (SSE/WebSocket) menor al tiempo de inactividad.
- Probar el cambio de controlador primero en un clúster de pruebas.

**Qué NO hacer**
- Crear un `LoadBalancer` por cada servicio.
- Adoptar un controlador sin revisar su estado de soporte.
- Usar anotaciones propietarias en todos lados (te atan a un controlador).
- Exponer paneles internos (Grafana, Argo CD) sin autenticación y sin WAF.
- Depender de `X-Forwarded-For` sin saber qué proxys lo añaden (se puede falsificar).
- Poner TLS "de mentira" (certificados autofirmados) en producción.

---

## 8. Límites, costos y versiones
- El controlador consume CPU/memoria **de tus nodos** (NGINX, Istio); AGC se factura aparte como recurso de Azure (unidades de capacidad + tráfico).
- Cada `Service` `LoadBalancer` añade IP pública/balanceador y su costo.
- Gateway API tiene versiones y canales de soporte (estándar/experimental): *verifica qué recursos soporta tu controlador*.
- Nombres de IngressClass, anotaciones y comandos `az aks approuting` cambian entre versiones.

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
