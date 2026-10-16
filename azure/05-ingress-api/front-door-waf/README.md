# Azure · Ingress y API · Front Door (con WAF)

## 1. Qué es

**Azure Front Door es la puerta de entrada *global* de tus aplicaciones web y APIs.** Es una red de puntos de presencia (POP) de Microsoft repartidos por el mundo: el usuario se conecta al más cercano, ahí se termina el TLS, se aplica el WAF, se sirve desde caché si se puede y, si no, la petición viaja por la red troncal de Microsoft hasta el origen sano más cercano.

Analogía: **una cadena de recepciones en aeropuertos de todo el mundo** que conocen tu edificio. El visitante entra por la recepción más cercana a él, le revisan la identidad y las maletas allí mismo, y desde allí lo llevan en transporte privado a tu sede (origen). Si una sede se incendia, lo mandan a otra.

| Concepto | Resumen |
|---|---|
| Capa | 7 (HTTP/HTTPS) |
| Alcance | **Global** (anycast; borde de Microsoft) |
| Qué hace | Aceleración, TLS en el borde, enrutamiento, caché/CDN, WAF, failover entre regiones |
| SKUs | **Standard** y **Premium** (Premium añade WAF gestionado, protección de bots y **Private Link hacia los orígenes**). *Front Door clásico está retirado/en retiro: migra, verifica la fecha oficial* |
| Orígenes | Cualquier endpoint HTTP(S) accesible: App Service, Application Gateway, APIM, AKS, Storage, otra nube |

---

## 2. Cómo funciona por dentro

```
Usuario (Lima) ──► DNS: api.modalima.example → CNAME → xxx.z01.azurefd.net
                        │ (anycast: llega al POP más cercano)
                  ┌─────▼──────────────────────────────┐
                  │ POP de Front Door                  │
                  │  TLS termina aquí · WAF · reglas   │
                  │  ¿en caché? ──sí──► respuesta      │
                  └─────┬──────────────────────────────┘
                        │ no → red troncal de Microsoft
                        ▼
        Grupo de orígenes (sondas de salud + balanceo)
          ├─ Origen A (East US 2)  prioridad 1, peso 50
          ├─ Origen B (East US 2)  prioridad 1, peso 50
          └─ Origen C (Brazil South) prioridad 2  ← respaldo
```

### 2.1 Los objetos (jerarquía)

| Objeto | Qué es | Detalle |
|---|---|---|
| **Perfil** | El contenedor de todo | Elige SKU: Standard o Premium |
| **Endpoint** | Nombre público `*.z01.azurefd.net` | Puede haber varios por perfil |
| **Dominio personalizado** | Tu nombre (`api.modalima.example`) | Certificado **gestionado** (gratuito, renovación automática) o propio desde Key Vault; validación con registro TXT `_dnsauth` |
| **Grupo de orígenes** | Conjunto de servidores equivalentes | Define las **sondas de salud** y el **balanceo** |
| **Origen** | Un servidor concreto | Host, puertos, **cabecera Host al origen**, prioridad, peso, Private Link |
| **Ruta** | Enlaza dominios/patrones con un grupo de orígenes | Patrones (`/api/*`), protocolos, redirección a HTTPS, caché, compresión |
| **Conjunto de reglas** | Reglas condición→acción | Redirigir, reescribir URL, modificar cabeceras, anular configuración de ruta |
| **Política WAF** | Reglas de seguridad | Se asocia a dominios mediante una **política de seguridad** |

### 2.2 Balanceo entre orígenes
Para cada petición, Front Door elige el origen así:
1. Solo entre los **sanos** (según las sondas).
2. Solo los de **mayor prioridad** disponible (1 antes que 2). Esto da *failover*.
3. Entre ellos, los que están dentro de la **latencia adicional permitida** respecto al más rápido (`additional latency`).
4. Reparte por **peso**.

**Sondas de salud:** cada POP sondea cada origen (por defecto cada 30 s, método `HEAD` recomendado). Con cientos de POP, tu origen recibe **muchas** sondas: la ruta debe ser barata. Se necesitan `X` muestras correctas de `Y` para considerar sano.

### 2.3 Caché y compresión
- Puedes cachear respuestas en el borde; el TTL sale de `Cache-Control` / `Expires` del origen, o se fuerza en la ruta.
- Control de **cadena de consulta**: ignorar, usar todas, o listas.
- Compresión de tipos de contenido (gzip/brotli).
- **Purga** de rutas tras un despliegue (`/*` o específica).
- Para **APIs dinámicas** normalmente desactiva la caché; para estáticos (imágenes, JS) actívala.

### 2.4 Reglas (rule sets)
Ejemplos: redirigir `www.` al dominio raíz; reescribir `/v1/*` a `/api/v1/*`; añadir `Strict-Transport-Security`; quitar cabeceras del servidor; elegir otro grupo de orígenes según la cabecera o el país.

### 2.5 Cabeceras
| Cabecera | Quién la pone | Para qué |
|---|---|---|
| `X-Azure-FDID` | Front Door → origen | **Identifica tu perfil**: el origen verifica que la petición vino de **tu** Front Door |
| `X-Azure-Ref` | Front Door (en la respuesta) | Id de referencia; imprescindible para soporte y correlación |
| `X-Forwarded-For` | Front Door | IP del cliente (puede contener varias separadas por coma) |
| `X-Azure-ClientIP` / `X-Azure-SocketIP` | Front Door | IP del cliente / de la conexión |
| `X-Forwarded-Host` / `X-Forwarded-Proto` | Front Door | Host y protocolo originales |
| `X-FD-HealthProbe` | Front Door | Marca las peticiones de sonda (valor `1`) |

### 2.6 Cómo cerrar el origen para que solo entre Front Door
Sin esto, cualquiera que descubra la dirección del origen **se salta el WAF**.

| Método | Cómo | Nota |
|---|---|---|
| **Etiqueta de servicio + cabecera** | NSG/restricciones: permitir `AzureFrontDoor.Backend` **y** validar `X-Azure-FDID` = id de tu perfil | La etiqueta cubre a *todos* los Front Door del mundo; la cabecera te distingue |
| **Private Link (Premium)** | Front Door llega al origen por un Private Endpoint administrado; el origen no tiene acceso público | Más seguro; aprobación de la conexión en el origen |

### 2.7 TLS
- TLS 1.2+ en el borde; política mínima configurable en dominios personalizados.
- Hacia el origen: HTTPS recomendado; con validación del nombre del certificado (`certificate name check`).
- Certificados gestionados se renuevan solos si el CNAME apunta a Front Door.

### 2.8 WAF en Front Door
| Característica | Standard | Premium |
|---|---|---|
| Reglas personalizadas (IP, geo, cabeceras, tasa) | ✔ | ✔ |
| Reglas gestionadas (OWASP/Default Rule Set) | ✘ | ✔ |
| Protección de bots | ✘ | ✔ |
| Private Link a orígenes | ✘ | ✔ |

Modos **Detection** y **Prevention**; exclusiones; acción por regla (Allow, Block, Log, Redirect, **CAPTCHA/JS challenge** donde esté disponible). *Verifica la matriz de funciones vigente.*

### 2.9 Límites de tiempo
El tiempo de espera de respuesta del origen es configurable (por defecto ~60 s; máximo del orden de minutos): si tu API tarda más, Front Door devuelve **504**. Para tareas largas usa el patrón `202 Accepted` + consulta de estado.

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- Usuarios en **varias regiones** que necesitan baja latencia.
- **Failover automático** entre regiones activo/activo o activo/respaldo.
- Una sola capa de **WAF, TLS y caché** para muchos orígenes.
- Servir **contenido estático** (Blob, SPAs de React/Angular) con CDN.
- Ocultar los orígenes (Private Link) y absorber picos y ataques volumétricos HTTP.

| NO lo uses si | Alternativa |
|---|---|
| Todo vive en **una** región y en red privada | [Application Gateway](../application-gateway/README.md) |
| Solo necesitas políticas de API (JWT, cuotas) | [APIM](../apim/README.md) |
| Tráfico que no es HTTP(S) | Load Balancer / Traffic Manager (DNS) |
| El origen debe ser completamente privado sin Premium | Application Gateway privado |
| Respuestas muy personalizadas que no se pueden cachear y un solo país | Un gateway regional puede costar menos |

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **POP / borde** | Punto de presencia cercano al usuario | Lima, Bogotá, São Paulo |
| **Anycast** | Misma IP anunciada desde muchos lugares; la red te lleva al más cercano | — |
| **Origen** | Tu servidor real | `app-pedidos.azurewebsites.net` |
| **Origin host header** | `Host` que Front Door envía al origen | Mismo que el nombre del origen |
| **Failover** | Pasar a otro origen cuando falla el principal | Brasil como respaldo |
| **Purga** | Borrar la caché de una ruta | `/img/*` tras un despliegue |
| **Política de seguridad** | Enlaza WAF con dominios/rutas | WAF en `api.modalima.example` |
| **Latencia adicional** | Tolerancia para considerar "igual de rápido" | 50 ms |
| **Split TCP** | La conexión del usuario termina en el borde y otra dura va al origen | Menos latencia en handshake |

---

## 5. Cómo se usa
1. Crear **perfil** (Premium si quieres WAF gestionado o Private Link).
2. Crear **endpoint**, **grupo de orígenes** (sonda `HEAD` a una ruta barata) y **orígenes**.
3. Crear la **ruta** (patrones, HTTPS, caché según el tipo de contenido).
4. Añadir el **dominio personalizado**: registro `_dnsauth` TXT y CNAME hacia el endpoint.
5. Crear la **política WAF** (Detection primero) y la **política de seguridad** que la enlaza con el dominio.
6. **Cerrar el origen** (FDID/etiqueta o Private Link).
7. Activar diagnósticos (`FrontDoorAccessLog`, `FrontDoorWebApplicationFirewallLog`, `FrontDoorHealthProbeLog`).

Archivos: [Terraform](ejemplos/terraform/main.tf) · [CLI](ejemplos/cli/frontdoor.sh) · [KQL](ejemplos/kql/kql-frontdoor.md).

### Comprobaciones rápidas
```bash
az afd endpoint show -g rg-estudio-afd --profile-name afd-modalima -n ep-modalima --query hostName
az afd origin-group show -g rg-estudio-afd --profile-name afd-modalima -n og-pedidos
curl -sI https://api.modalima.example/ | grep -i -E "x-azure-ref|x-cache|server"
# ¿El origen directo está cerrado? (debe fallar / dar 403)
curl -skI https://app-pedidos-modalima.azurewebsites.net/
```
Cabecera de respuesta `x-cache`: `TCP_HIT` (caché) o `TCP_MISS` (fue al origen).

---

## 6. Seguridad
- **WAF** en Prevention (tras Detection), con reglas gestionadas + límite de tasa + filtro geográfico.
- **Cerrar el origen:** Private Link (Premium) o restricción por etiqueta + validación de `X-Azure-FDID`.
- **TLS** 1.2+, HSTS, redirección HTTP→HTTPS en la ruta.
- **Certificados** gestionados o de Key Vault con alerta de expiración.
- **Dominios:** vigila el *subdomain takeover*: no dejes CNAME apuntando a endpoints eliminados.
- **No cachear** respuestas con datos personales (`Cache-Control: private/no-store`).
- Logs a Log Analytics con retención de auditoría.

### IAM de este servicio

| Quién | Qué hace | Rol mínimo |
|---|---|---|
| Equipo de plataforma | Crear/operar perfiles, rutas y orígenes | *Contributor* sobre el perfil (o *Azure Front Door and CDN Contributor*) |
| Equipo de seguridad | Administrar la política WAF | *Contributor* sobre la política WAF (o rol personalizado) |
| Perfil de Front Door | Leer certificados propios | Identidad administrada con *Key Vault Secrets User* |
| Aprobador de Private Link | Aceptar la conexión en el origen | Rol con permiso sobre las conexiones privadas del origen |
| Auditoría | Ver configuración | *Reader* |

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- Elegir **Premium** si necesitas WAF gestionado, bots o Private Link.
- Sondas `HEAD` a una ruta barata y estable; muestras razonables.
- Un grupo de orígenes con **prioridades** para failover y **pesos** para repartir.
- Cachear solo lo cacheable; definir `Cache-Control` en el origen; purgar tras desplegar.
- Registrar el `X-Azure-Ref` en tus logs de aplicación.
- Cerrar el origen; probar que el acceso directo falla.
- Usar conjuntos de reglas para redirecciones y cabeceras de seguridad.
- Gestionarlo con Terraform/Bicep.

**Qué NO hacer**
- Dejar el origen con acceso público abierto (se salta el WAF).
- Cachear respuestas personalizadas o autenticadas sin `Vary` o sin pensar.
- Sondas pesadas que consultan la base de datos (miles de sondas por minuto).
- Confiar en `X-Azure-FDID` sin combinarla con restricción de red.
- Usar la etiqueta `AzureFrontDoor.Backend` como única protección.
- Esperar respuestas de >60 s sin ajustar tiempos o rediseñar.
- Apuntar un CNAME a un endpoint que ya no existe.

---

## 8. Límites, costos y versiones
- Costo: **tarifa base por perfil** (Standard/Premium) + **peticiones** + **transferencia de salida** desde el borde + componentes del WAF.
- Los límites (rutas por endpoint, dominios, orígenes, tamaño de regla, tiempo de espera) cambian: *verifica la página de límites*.
- La propagación de cambios de configuración puede tardar minutos; la purga también.
- El SKU clásico se retira: no lo uses en diseños nuevos.
- Premium con Private Link: la conexión privada debe ser **aprobada** en el recurso de origen.

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
