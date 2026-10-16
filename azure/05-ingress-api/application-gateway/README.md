# Azure · Ingress y API · Application Gateway (con WAF)

## 1. Qué es

**Application Gateway es un balanceador de carga de capa 7 (HTTP/HTTPS), regional, que vive dentro de tu VNet y que opcionalmente incluye un firewall de aplicaciones web (WAF).** Recibe las peticiones, termina el TLS, decide a qué grupo de servidores enviarlas mirando host y ruta, comprueba que estén sanos y, con WAF, bloquea ataques comunes (inyección SQL, XSS…).

Analogía: **el control de seguridad de la entrada del edificio de una ciudad (región)**. Revisa quién eres (TLS), lee el papel que traes (host y ruta), te revisa la mochila (WAF) y te manda al piso correcto (backend pool). Si el piso está cerrado (backend no sano), te dice "502".

| Concepto | Resumen |
|---|---|
| Capa | 7 (entiende HTTP: host, ruta, cabeceras, cookies) |
| Alcance | **Regional** (una región, con zonas de disponibilidad) |
| Dónde vive | En una **subred dedicada** de tu VNet |
| Versión | **v2** (`Standard_v2`, `WAF_v2`): autoescala y zonas. *La v1 está retirada o en retiro: verifica la fecha oficial y migra.* |
| WAF | Política con reglas OWASP/Default Rule Set, reglas personalizadas, bots, exclusiones |

---

## 2. Cómo funciona por dentro

```
Cliente ──► IP frontend (pública y/o privada)
              │
        [Listener]  puerto · protocolo · host (SNI) · certificado
              │
        [WAF policy]  ◄── inspecciona ──► permite / bloquea / registra
              │
        [Regla de enrutamiento]  básica  o  por rutas (url path map)
              │
        [Backend settings / HTTP settings]  puerto · protocolo · cookie · cabecera Host · timeout
              │          ▲
              │          └── [Sonda de salud]  decide si cada backend está sano
              ▼
        [Backend pool]  App Service · IP privadas (AKS interno, VM) · FQDN · APIM
```

### 2.1 Las piezas

| Pieza | Para qué sirve | Detalle que importa |
|---|---|---|
| **Frontend IP** | Dirección de entrada | Pública (Standard, estática) y/o privada. Los modos solo-privado requieren funciones específicas: *verifica la disponibilidad* |
| **Frontend port** | Puerto de escucha | 80, 443… |
| **Listener** | Qué escucha | *Basic* (un sitio) o *Multi-site* (varios hosts con SNI y comodines) |
| **Certificado SSL** | TLS en el listener | Subido o **referenciado en Key Vault** (recomendado) |
| **Regla de enrutamiento** | Une listener con destino | *Basic* (todo a un backend) o *Path-based* (ruta → backend). `priority` obligatoria en v2 |
| **Backend pool** | Destinos | IP, FQDN, VM, VMSS, App Service |
| **Backend settings / HTTP settings** | Cómo hablarle al backend | Protocolo (HTTP/HTTPS), puerto, **cabecera Host**, afinidad por cookie, *timeout* de solicitud, drenaje de conexiones |
| **Sonda de salud (probe)** | Decide si el backend está sano | Ruta, intervalo, umbral, códigos esperados (200–399 por defecto) |
| **Rewrite rule set** | Modificar cabeceras y URL | Agregar/quitar cabeceras, reescribir rutas, con condiciones |
| **Redirect configuration** | Redirecciones | HTTP → HTTPS, o a otro sitio |
| **WAF policy** | Reglas de seguridad | Una política global, por listener o por ruta |
| **Autoscale** | Capacidad | `min`/`max` de unidades; se factura por *unidades de capacidad* |
| **Zonas** | Alta disponibilidad | Distribuye las instancias en zonas de disponibilidad |

### 2.2 La cabecera Host (la causa nº1 de dolores de cabeza)
Application Gateway reenvía la petición al backend con una cabecera `Host`. Hay dos opciones en la configuración HTTP:
- **Mantener el host original** (`api.modalima.example`): el backend debe aceptarlo (bueno para apps con enlaces absolutos o multi-tenant).
- **Tomar el nombre del backend** (`miapp.azurewebsites.net`): obligatorio para muchos App Service, que enrutan por nombre de host.

Si el backend espera otro host, verás 404, redirecciones a `miapp.azurewebsites.net` o cookies con dominio equivocado. El gateway también añade `X-Original-Host`.

### 2.3 Cabeceras que añade
| Cabecera | Contenido |
|---|---|
| `X-Forwarded-For` | IP del cliente **con puerto** (`203.0.113.7:51234`) en App Gateway |
| `X-Forwarded-Proto` | `https` o `http` |
| `X-Forwarded-Port` | Puerto del cliente hacia el gateway |
| `X-Original-Host` | Host que pidió el cliente |
| `X-AppGW-Trace-Id` | Identificador de la solicitud, útil para correlacionar con los logs |

### 2.4 Sondas de salud
- Sin sonda personalizada, el gateway usa una sonda por defecto a `/` con el host del backend.
- Con sonda personalizada: protocolo, **host**, ruta, intervalo, *timeout*, umbral de fallos, códigos aceptados.
- Si **todos** los backends están no sanos, el gateway responde 502. (Si fallan todos, v2 sigue enviando a todos como último recurso: no confíes en eso.)
- Una sonda debe ser **barata y sin autenticación**, y no depender de una base de datos que no es tuya.

### 2.5 TLS
| Modo | Qué ocurre | Cuándo |
|---|---|---|
| **Terminación** | TLS termina en el gateway; hacia el backend va HTTP | Red privada de confianza, simplicidad |
| **Extremo a extremo** | TLS hasta el gateway y otro TLS hacia el backend | Requisitos de cumplimiento; el backend necesita certificado válido o el raíz como *trusted root* |
| **Passthrough** | No soportado en L7 | Usa un balanceador L4 si lo necesitas |

**Política TLS:** define la versión mínima (TLS 1.2) y los cifrados con una política predefinida. *Verifica la política vigente.*

### 2.6 Certificados desde Key Vault
1. Identidad administrada asignada por el usuario en el gateway.
2. Rol **Key Vault Secrets User** para esa identidad sobre el vault (o permisos equivalentes).
3. En el listener, el certificado referencia el **secreto sin versión** (`.../secrets/cert-api`): el gateway lo vuelve a leer periódicamente (cada ~4 horas) y rota solo.
4. Si el vault tiene firewall, la red del gateway debe poder llegar (punto de conexión de servicio o servicios de confianza): *verifica la guía actual*.

### 2.7 Red y NSG (v2)
| Tema | Regla |
|---|---|
| Subred | **Dedicada** (solo App Gateway). `/24` recomendado para escalar |
| NSG entrada | **GatewayManager** puertos `65200-65535` (infraestructura de Azure), **AzureLoadBalancer**, e **Internet** a los puertos de tus listeners (80/443) |
| UDR | En v2 una ruta `0.0.0.0/0` hacia un firewall/NVA suele no estar soportada salvo en implementaciones específicas: *verifica* |
| DNS | El gateway resuelve los FQDN de los backends con el DNS de la VNet (zona privada si el backend tiene Private Endpoint) |
| Backend privado | Si el backend es un App Service con Private Endpoint, el pool usa el FQDN y resuelve a la IP privada ([Private Endpoint](../../01-red/private-endpoint-dns/README.md)) |

### 2.8 WAF en detalle
**Modo:** *Detection* (solo registra) o *Prevention* (bloquea con 403). Empieza en Detection.

**Reglas gestionadas:** conjunto OWASP CRS (3.2) o el **Default Rule Set** de Microsoft (versiones recientes) más el *Bot Manager Rule Set*. Las reglas puntúan por **anomalía**: cada coincidencia suma puntos y el bloqueo ocurre al pasar el umbral.

| Elemento | Qué hace |
|---|---|
| **Reglas personalizadas** | Tus propias condiciones (IP, geografía, cabecera, tasa) con prioridad y acción (Allow, Block, Log, Redirect) |
| **Exclusiones** | Ignorar un campo concreto (cabecera, cookie, argumento) para una regla o todas |
| **Deshabilitar regla** | Último recurso, mejor por ruta |
| **Política por listener/ruta** | Reglas distintas por sitio o URI |
| **Límite de inspección del cuerpo** | Solo se inspecciona hasta cierto tamaño; los archivos grandes tienen su propio límite (verifica los valores) |
| **Rate limiting** | Regla personalizada por cliente o IP |

**Logs:** categoría `ApplicationGatewayFirewallLog` (regla, mensaje, URI, acción). Es el primer sitio a mirar ante un 403.

### 2.9 Registros y métricas
| Qué | Para qué |
|---|---|
| `ApplicationGatewayAccessLog` | Cada petición: código, tiempo, backend, trace id |
| `ApplicationGatewayFirewallLog` | Decisiones del WAF |
| `ApplicationGatewayPerformanceLog` | Rendimiento (v1) |
| Métrica *Unhealthy host count* | Backends no sanos |
| Métrica *Backend response status* | 4xx/5xx del backend vs del gateway |
| Métrica *Capacity units* | Para ajustar autoscale y costo |

### 2.10 Otras funciones
- **WebSocket y HTTP/2:** soportados (verifica el alcance de gRPC/HTTP2 hacia el backend).
- **Afinidad por cookie** (`ApplicationGatewayAffinity`): útil si tu app guarda sesión local; mejor evitarla.
- **Drenaje de conexiones:** al retirar un backend deja terminar las conexiones en curso.
- **Reescritura de URL y cabeceras:** por ejemplo `/api/pedidos` → `/pedidos`.
- **Private Link:** exponer el gateway por una conexión privada a otras redes (verifica disponibilidad).

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- Entrada HTTP(S) **regional** con WAF a servicios dentro de la VNet (App Service con Private Endpoint, AKS interno, VMs).
- Varios sitios/hosts detrás de una IP con TLS por sitio.
- Enrutamiento por ruta (`/pedidos` → pool A, `/catalogo` → pool B).
- Quitar la responsabilidad del TLS y del WAF de las aplicaciones.

| NO lo uses si | Alternativa |
|---|---|
| Necesitas entrada **global** con failover entre regiones y CDN | [Front Door](../front-door-waf/README.md) (y Application Gateway detrás si hace falta) |
| Solo necesitas autenticación, cuotas y portal para consumidores de API | [APIM](../apim/README.md) |
| Todo vive en AKS y quieres Gateway API | [Application Gateway for Containers](../ingress-aks/README.md) |
| El tráfico no es HTTP (TCP/UDP) | Load Balancer o Azure Firewall |
| Quieres una solución barata para una app de prueba | App Service ya incluye HTTPS; no pagues un gateway |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Unidad de capacidad** | Medida de consumo (conexiones, throughput, cómputo) que se factura | min 2, max 10 |
| **SNI** | Extensión TLS para elegir certificado según el nombre | `api.` y `web.` en la misma IP |
| **Backend health** | Estado de cada backend según la sonda | `Healthy` / `Unhealthy` |
| **Anomaly scoring** | El WAF suma puntos por reglas y bloquea al pasar el umbral | 5 puntos = bloqueo |
| **False positive** | El WAF bloquea tráfico legítimo | Un comentario con comillas |
| **Trusted root certificate** | Certificado raíz del backend para TLS extremo a extremo | CA interna |
| **Path-based rule** | Una regla que enruta según la ruta | `/pedidos/*` |
| **Connection draining** | Terminar conexiones en curso al retirar un backend | 30 s |
| **Probe match** | Códigos/cuerpo que se consideran "sano" | `200-399` |

---

## 5. Cómo se usa

1. Crear la **subred dedicada** y su NSG ([ejemplos/terraform/main.tf](ejemplos/terraform/main.tf)).
2. Crear la **IP pública Standard** y la **identidad** con acceso al Key Vault.
3. Crear el gateway con autoscale y zonas; definir listeners, pools, backend settings, sondas y reglas.
4. Crear la **política WAF**; asociarla; empezar en *Detection*.
5. Activar diagnósticos (access y firewall logs) hacia Log Analytics.
6. Revisar *Backend health*, probar con `curl --resolve`, subir a *Prevention*.

CLI de referencia: [ejemplos/cli/appgw.sh](ejemplos/cli/appgw.sh). Consultas KQL para los logs: [ejemplos/kql/kql-appgw.md](ejemplos/kql/kql-appgw.md).

### Comprobaciones rápidas
```bash
az network application-gateway show-backend-health -g rg-estudio-agw -n agw-modalima -o table
az network application-gateway waf-policy show -g rg-estudio-agw -n waf-modalima --query policySettings
curl -vk --resolve api.modalima.example:443:<IP-del-gateway> https://api.modalima.example/pedidos/health
openssl s_client -connect <IP>:443 -servername api.modalima.example </dev/null | openssl x509 -noout -subject -dates
```

---

## 6. Seguridad
- **WAF_v2 en Prevention** (tras una fase de Detection) en cualquier entrada pública.
- **TLS 1.2+** y política de cifrados moderna; certificados en **Key Vault** con alertas de expiración.
- El backend **solo acepta tráfico del gateway** (restricciones de acceso del App Service por subred/etiqueta de servicio, NSG del AKS).
- **No** exponer el backend con IP pública "por ahora".
- Reglas personalizadas para bloquear países, IPs y limitar tasa.
- Cabeceras de seguridad (HSTS, etc.) con *rewrite rules*.
- Registro completo de acceso y WAF, con retención acorde a auditoría.

### IAM de este servicio

| Quién | Qué hace | Rol mínimo |
|---|---|---|
| Equipo de red | Crear y operar el gateway | *Network Contributor* sobre el recurso y la subred |
| Equipo de seguridad | Administrar la política WAF | *Network Contributor* sobre la política (o un rol personalizado acotado) |
| Identidad del gateway | Leer certificados | *Key Vault Secrets User* (o *Certificates User*) sobre el vault |
| Auditoría | Leer la configuración | *Reader* |
| Quien despliega con Terraform | Crear todo | *Contributor* + *User Access Administrator* donde asigne roles |

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- SKU **v2**, 3 zonas y `min` de al menos 2 unidades en producción.
- Subred dedicada con holgura (`/24`).
- Sondas simples, rápidas y sin autenticación; ruta que realmente exista.
- Verificar la cabecera Host del backend desde el primer día.
- Empezar WAF en **Detection**, medir, excluir con precisión, pasar a **Prevention**.
- Certificados desde Key Vault **sin versión** para rotación automática.
- Enviar logs de acceso y WAF a Log Analytics y alertar sobre *Unhealthy host count* y 5xx.
- Mantener la configuración como código (Terraform/Bicep).

**Qué NO hacer**
- Apagar el WAF para resolver un falso positivo.
- Mezclar otros recursos en la subred del gateway.
- Bloquear `GatewayManager 65200-65535` en el NSG (el gateway queda en estado de error).
- Usar sondas que dependan de una base de datos o requieran un token.
- Poner timeouts enormes para ocultar un backend lento.
- Confiar en `X-Forwarded-For` sin saber que viene con puerto y sin saber quién lo envía.
- Dejar el backend accesible sin pasar por el gateway.
- Dimensionar `min` en 0 para "ahorrar" si necesitas latencia estable.

---

## 8. Límites, costos y versiones
- Costo = **tarifa fija por hora del gateway + unidades de capacidad consumidas** (+ datos). WAF_v2 cuesta más que Standard_v2.
- Escalar toma unos minutos: `min` demasiado bajo causa picos de latencia en subidas bruscas.
- Límites de reglas, listeners, certificados, backends y tamaño de cuerpo cambian con el tiempo: *verifica la página de límites*.
- La v1 se retira: no la uses en nuevos diseños.
- Application Gateway for Containers es otro producto, orientado a Kubernetes ([Ingress en AKS](../ingress-aks/README.md)).

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
