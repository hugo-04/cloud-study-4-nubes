# 06 · Ingress, Application Gateway y API Management

Cómo entra el tráfico a tus servicios: **balanceadores**, **Ingress en AKS**, **Application Gateway (WAF)** y **API Management (APIM)**, con sus equivalentes en **AWS**, **OCI** y **GCP**.

---

## 1. Qué es (con analogía)

Un edificio corporativo:

| Pieza | Analogía |
|---|---|
| **Balanceador de carga** | El portero que reparte a la gente entre las ventanillas libres |
| **Ingress / Gateway API** | El recepcionista que dirige: "ventas, piso 2; soporte, piso 3" (por nombre y ruta) |
| **WAF** | El control de seguridad: revisa bolsos y rechaza lo peligroso |
| **API Management** | La ventanilla de atención: verifica quién eres, cuántas veces puedes preguntar, traduce lo que pides y anota todo |

Cada capa resuelve un problema distinto. Se **combinan**, no se sustituyen.

---

## 2. Mapa de capas y equivalencias

| Capa | Qué hace | Azure | AWS | OCI | GCP |
|---|---|---|---|---|---|
| L4 (TCP/UDP) regional | Reparte conexiones | Load Balancer | Network Load Balancer | Network Load Balancer | Network LB (pass-through) |
| L7 (HTTP) regional | Enruta por host/ruta, TLS, WAF | **Application Gateway** | Application Load Balancer | Load Balancer (flexible) | Application LB (regional) |
| L7 global | Entrada global, CDN, WAF | **Front Door** | CloudFront + Global Accelerator | (CDN/WAF de terceros o regionales) | Global external Application LB + Cloud CDN |
| DNS global | Reparte por DNS | Traffic Manager | Route 53 (políticas de ruteo) | Traffic Management Steering | Cloud DNS (routing policies) |
| WAF | Filtra ataques web | WAF en App Gateway / Front Door | AWS WAF | OCI WAF | Cloud Armor |
| Ingress de Kubernetes | Dirige tráfico dentro del clúster | NGINX, AGIC, AGC, Gateway API | AWS Load Balancer Controller | OCI native ingress controller | GKE Ingress / Gateway |
| **API Management** | Seguridad, límites, versiones, portal | **API Management** | API Gateway (REST/HTTP) | API Gateway | API Gateway / **Apigee** |

### Diferencias reales

- **APIM** se aprovisiona como **instancia** (tiers por capacidad); el **API Gateway de AWS** se cobra **por petición**.
- Las políticas de APIM son **XML** (muy expresivas). AWS usa **autorizadores, planes de uso y plantillas**; OCI usa políticas de **solicitud** declarativas; **Apigee** tiene su propio modelo de políticas y es el más completo (y más pesado).
- **Front Door** y **CloudFront** son entradas **globales**; **Application Gateway** y **ALB** son **regionales**.
- En **GCP** el balanceador de aplicaciones **externo global** es una sola IP anycast para todo el mundo.

---

## 3. Ingress en AKS

### 3.1 Service LoadBalancer vs Ingress

| | Service tipo LoadBalancer | Ingress / Gateway API |
|---|---|---|
| Capa | L4 | **L7 (HTTP)** |
| Un balanceador por servicio | Sí (costo) | **No**: uno para muchos servicios |
| Rutas por host y ruta | No | **Sí** |
| TLS, redirecciones, reescrituras | No | Sí |

### 3.2 Opciones de controlador

| Opción | Nota |
|---|---|
| **NGINX** (community) | Muy extendido. **El proyecto ingress-nginx de la comunidad anunció su retiro**; verifica el estado actual antes de adoptarlo. |
| **Application Routing add-on** de AKS | Ingress administrado por Azure; verifica su base y calendario de soporte. |
| **AGIC** (Application Gateway Ingress Controller) | Usa un Application Gateway como entrada del clúster. |
| **Application Gateway for Containers** | Evolución para Kubernetes con soporte de **Gateway API**. |
| **Malla de servicios** (Istio gateway) | Cuando ya usas malla. |

> Tendencia: **Gateway API** es el sucesor de Ingress. Aprende los dos: Ingress para leer lo existente, Gateway API para lo nuevo.

### 3.3 Ingress (ejemplo)

```yaml
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: api-pedidos
  namespace: modalima
spec:
  ingressClassName: nginx
  tls:
    - hosts: ["api.modalima.example"]
      secretName: tls-api
  rules:
    - host: api.modalima.example
      http:
        paths:
          - path: /pedidos
            pathType: Prefix
            backend:
              service:
                name: svc-pedidos
                port:
                  number: 80
          - path: /catalogo
            pathType: Prefix
            backend:
              service:
                name: svc-catalogo
                port:
                  number: 80
```

### 3.4 Gateway API (ejemplo)

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: pedidos
  namespace: modalima
spec:
  parentRefs:
    - name: gw-modalima
  hostnames: ["api.modalima.example"]
  rules:
    - matches:
        - path: { type: PathPrefix, value: /pedidos }
      backendRefs:
        - name: svc-pedidos
          port: 80
```

### 3.5 Interno o público

- **Público:** el controlador se publica con IP pública. Solo para entradas reales de internet.
- **Interno:** anotación de balanceador interno (ver módulo 02) y APIM / Application Gateway delante.

---

## 4. Application Gateway en detalle

### 4.1 Piezas

```
Cliente → [IP frontend] → [Listener (puerto/host/TLS)] → [Regla]
                                              │
                          [Configuración HTTP + sonda de salud]
                                              │
                                      [Pool de backends]
```

| Pieza | Para qué |
|---|---|
| Listener | Escucha por IP, puerto, host y certificado |
| Regla | Une listener con backend (básica o por ruta) |
| **Backend pool** | Destinos: VMs, App Service, IP internas (AKS) |
| **Configuración HTTP** | Puerto, protocolo, cookies, cabecera Host |
| **Sonda de salud** | Decide si un backend está sano |
| **WAF** | Reglas OWASP (modo *Detection* o *Prevention*) |

### 4.2 Reglas prácticas

| Tema | Detalle |
|---|---|
| SKU | **v2** (`Standard_v2` / `WAF_v2`): autoscaling y zonas |
| Subnet | **Dedicada** (con holgura de IP para escalar) |
| NSG de la subnet (v2) | Permitir entrada del rango de **GatewayManager** (puertos 65200–65535) y **AzureLoadBalancer**; verifica la lista vigente |
| TLS | Terminación en el gateway, o **extremo a extremo** si el backend también usa HTTPS |
| Certificados | Desde **Key Vault** con identidad administrada |
| Cabecera Host | Debe coincidir con lo que espera el backend (error clásico) |

### 4.3 Front Door vs Application Gateway

| | Front Door | Application Gateway |
|---|---|---|
| Alcance | **Global** | **Regional** |
| Dónde vive | Borde de Microsoft | Dentro de tu VNet |
| Ideal para | Entrada global, CDN, failover entre regiones | Entrada de una región, backends privados |
| Patrón común | Front Door → Application Gateway / APIM de cada región | |

---

## 5. API Management (APIM) en detalle

### 5.1 Conceptos

| Concepto | Qué es |
|---|---|
| **API** | Conjunto de operaciones expuestas (importadas de OpenAPI) |
| **Operación** | Un método y ruta (`GET /pedidos/{id}`) |
| **Producto** | Paquete de APIs con términos de uso |
| **Suscripción** | Clave que identifica a un consumidor de un producto |
| **Política** | Regla que se ejecuta en la petición/respuesta |
| **Named value** | Valor reutilizable (puede venir de Key Vault) |
| **Backend** | Definición reutilizable del servicio destino |
| **Versión / revisión** | Versión pública (v1, v2) / cambio interno sin romper |
| **Portal de desarrolladores** | Documentación y pruebas para consumidores |
| **Gateway** | El componente que atiende el tráfico (administrado o autoalojado) |

Tiers: Consumption, Developer, Basic, Standard, Premium y los **v2**. Cada uno tiene opciones de red, escalado y costo distintas; **verifica la tabla vigente**.

### 5.2 Flujo de una petición

```
Cliente
   │
   ▼
┌───────────── APIM ─────────────┐
│ inbound   → autenticar, limitar, transformar
│ backend   → llamar al servicio
│ outbound  → transformar la respuesta
│ on-error  → manejar errores
└────────────────────────────────┘
   │
   ▼
Backend (AKS / App Service / Functions)
```

### 5.3 Política de ejemplo

```xml
<policies>
  <inbound>
    <base />
    <!-- 1. Validar el token de Entra ID -->
    <validate-jwt header-name="Authorization" failed-validation-httpcode="401"
                  failed-validation-error-message="Token inválido">
      <openid-config url="https://login.microsoftonline.com/TENANT_ID/v2.0/.well-known/openid-configuration" />
      <audiences>
        <audience>api://modalima-pedidos</audience>
      </audiences>
    </validate-jwt>

    <!-- 2. Límite de llamadas por suscripción o IP -->
    <rate-limit-by-key calls="100" renewal-period="60"
        counter-key="@(context.Subscription?.Id ?? context.Request.IpAddress)" />

    <!-- 3. Correlación para el rastreo -->
    <set-header name="X-Correlation-Id" exists-action="skip">
      <value>@(Guid.NewGuid().ToString())</value>
    </set-header>

    <!-- 4. Llamar al backend con la identidad administrada de APIM -->
    <authentication-managed-identity resource="api://modalima-backend" />
    <set-backend-service base-url="https://api-interna.modalima.example/pedidos" />
  </inbound>

  <backend>
    <forward-request timeout="30" />
  </backend>

  <outbound>
    <base />
    <set-header name="X-Powered-By" exists-action="delete" />
  </outbound>

  <on-error>
    <base />
  </on-error>
</policies>
```

Otras políticas frecuentes: `cors`, `cache-lookup` / `cache-store`, `retry`, `mock-response`, `ip-filter`, `rewrite-uri`, `set-body`, `validate-content`.

### 5.4 CLI (crear e importar)

```bash
az apim create -g $RG -n apim-modalima-estudio \
  --publisher-email admin@example.com --publisher-name ModaLima \
  --sku-name Developer

az apim api import -g $RG --service-name apim-modalima-estudio \
  --api-id pedidos --path pedidos \
  --specification-format OpenApiJson --specification-path openapi.json
```
> Crear un APIM clásico puede tardar mucho (decenas de minutos). Revisa flags con `--help` y recuerda borrarlo al terminar el lab.

### 5.5 Versiones sin romper a nadie

| Esquema | Ejemplo |
|---|---|
| Por ruta | `/v1/pedidos`, `/v2/pedidos` |
| Por cabecera | `Api-Version: 2` |
| Por query | `?api-version=2` |

Regla: **no cambies una versión publicada**; añade una nueva y da un plazo de retiro.

### 5.6 Red

Los modos de red (público, VNet externa/interna, Private Endpoint), los requisitos de la subnet y los errores típicos de conectividad están en el módulo [02](../02-comunicacion-privada-y-diagnostico/README.md).

---

## 6. Flujo completo de extremo a extremo

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

Qué se valida en cada salto:

| Salto | Se valida |
|---|---|
| Usuario → entrada | Certificado, WAF, límites globales |
| Entrada → APIM | Host, ruta, certificado, regla de red |
| APIM → backend | Token (JWT / identidad administrada), límites, tiempo máximo |
| Backend → datos | Identidad administrada, red privada |

---

## 7. Casos de uso de vida real

### Caso 1 · API para un socio comercial
- **Problema:** un distribuidor necesitaba consultar stock; no se quería dar acceso directo al backend.
- **Solución:** un **producto** en APIM con suscripción propia, límite de 100 llamadas por minuto y solo las operaciones de lectura.
- **Resultado:** acceso controlado y medible; si abusan, solo se revoca su clave.
- **Lección:** APIM convierte "tu backend" en "un producto con reglas".

### Caso 2 · Falso positivo del WAF
- **Problema:** el formulario de comentarios devolvía 403 cuando alguien escribía ciertos símbolos.
- **Causa:** una regla OWASP bloqueaba el contenido.
- **Solución:** revisar los logs del WAF, y **excluir esa regla solo para esa ruta**, no apagar el WAF.
- **Lección:** empieza en *Detection*, mide, y pasa a *Prevention* con excepciones precisas.

### Caso 3 · Versión 2 sin romper la 1
- **Problema:** cambiar el formato de la respuesta de pedidos rompería a la app móvil antigua.
- **Solución:** `/v2/pedidos` nueva y `/v1` marcada como obsoleta con fecha de retiro.
- **Lección:** el contrato de una API es una promesa.

### Caso 4 · 502 "misterioso"
- **Problema:** el Application Gateway respondía 502 de pronto.
- **Pista:** el *backend health* mostraba "Unhealthy".
- **Causa:** la sonda apuntaba a `/health`, ruta que la nueva versión ya no tenía (404).
- **Solución:** corregir la ruta de la sonda.
- **Lección:** un 502 en el gateway casi siempre significa **backend no sano o no alcanzable**.

---

## 8. Qué hacer / qué NO hacer

**Qué hacer**
- Poner **WAF** en la entrada pública y arrancar en *Detection*.
- Terminar TLS con certificados desde **Key Vault**, con alerta de vencimiento.
- Validar **JWT** y aplicar **límites** en APIM, no solo en la aplicación.
- Usar identidad administrada de APIM hacia el backend.
- Mantener sondas de salud **simples y baratas**.
- Versionar las APIs y documentar con OpenAPI.
- Enviar logs y trazas a un workspace central.
- Gestionar APIM como código (APIOps, Terraform, Bicep).

**Qué NO hacer**
- Exponer el backend directamente a internet "por ahora".
- Apagar el WAF para "arreglar" un falso positivo.
- Dejar claves de suscripción como **única** seguridad.
- Poner lógica de negocio dentro de políticas XML.
- Cambiar una versión publicada sin avisar.
- Ignorar los tiempos máximos: un backend lento acaba como 504.
- Usar el tier equivocado: el Developer **no** es para producción (sin SLA).

---

## 9. Troubleshooting

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| 502 en Application Gateway | Backend no sano o no alcanzable | *Backend health*, sonda, NSG | Corregir sonda, ruta o red |
| 504 en Application Gateway | Backend lento o timeout | Tiempo de respuesta, configuración HTTP | Optimizar o ajustar tiempo |
| 403 del WAF | Regla OWASP activada | Logs del WAF | Excluir la regla en esa ruta |
| Error de certificado en el cliente | Cadena incompleta o nombre distinto | `openssl s_client -connect host:443 -servername host` | Certificado correcto y completo |
| Ingress no responde | Controlador sin IP, clase mal indicada | `kubectl describe ingress`, eventos | Corregir `ingressClassName` y servicio |
| 404 en el Ingress | Ruta o `pathType` no coincide | Reglas del Ingress | Ajustar ruta o reescritura |
| APIM 401 | Token inválido o audiencia equivocada | Traza de APIM | Corregir `audience` / emisor |
| APIM 429 | Límite de llamadas | Política `rate-limit` | Ajustar el límite o el cliente |
| APIM 500 | Error en política | Traza | Corregir expresión |
| APIM 502 / 504 | Backend inalcanzable o lento | Módulo 02 | Seguir RPDSI |

---

## 10. IAM del módulo

| Quién | Qué hace | Rol mínimo (Azure) |
|---|---|---|
| Equipo de APIs | Administrar APIs y políticas | API Management Service Contributor |
| Equipo de red | Administrar Application Gateway | Network Contributor |
| Application Gateway | Leer certificados | Key Vault Secrets User (o Certificate User) |
| APIM | Llamar al backend | Rol de aplicación en el backend / permiso en su API |
| Auditoría | Ver configuración | Reader |

---

## 11. Repaso y entrevista

**Repaso**
1. ¿Qué diferencia hay entre un balanceador L4 y uno L7?
2. ¿En qué se diferencia Front Door de Application Gateway?
3. ¿Por qué Gateway API sucede a Ingress?
4. ¿Qué hace cada sección de una política de APIM (inbound, backend, outbound, on-error)?
5. ¿Qué significa un 502 en Application Gateway?

**Entrevista**
- Diseña la entrada de una API pública con WAF, APIM y AKS privado.
- ¿Cómo publicas una v2 de una API sin romper a los clientes?
- ¿Cómo diferencias un problema del WAF de uno del backend?
