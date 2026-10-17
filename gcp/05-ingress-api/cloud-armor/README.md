# Google Cloud · Ingress y API · Cloud Armor

WAF y protección DDoS en el **borde de Google**, adjunto a los backend services de los balanceadores de aplicación (y algunos de red). Las **políticas de seguridad** tienen reglas por prioridad con condiciones (IP, país, expresiones CEL sobre la petición), **reglas WAF preconfiguradas** (inyección SQL, XSS, LFI, RCE… basadas en OWASP CRS), **limitación de tasa** y **Adaptive Protection** (detección de ataques L7 con aprendizaje).

## 1. Qué es

**Analogía:** el control de seguridad del aeropuerto antes de las puertas de embarque. Todos pasan por ahí (borde de Google); se revisa la lista de prohibidos (reglas), se detectan patrones sospechosos (WAF) y se limita cuántas veces alguien puede pasar por minuto (rate limiting).

```
 Cliente ─► borde de Google ─► Cloud Armor: política "tienda" ─► backend services
   p100  deny(403)   origin.region_code == 'XX'                       (bloqueo por país, si aplica)
   p200  throttle    request.path.startsWith('/v1/login')  10/min/IP   (fuerza bruta)
   p1000 deny(403)   evaluatePreconfiguredWaf('sqli-v33-stable')        (preview primero)
   p1001 deny(403)   evaluatePreconfiguredWaf('xss-v33-stable')
   p2147483647 allow  (regla por defecto)
 Adaptive Protection: alerta y regla sugerida ante un ataque L7
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Política de seguridad** | Lista de reglas con prioridad; tipo `CLOUD_ARMOR` (backend), `CLOUD_ARMOR_EDGE` (CDN/buckets) |
| **Regla** | Prioridad (menor gana), condición, acción (`allow`, `deny(403/404/502)`, `throttle`, `rate_based_ban`, `redirect`) |
| **Condiciones** | `srcIpRanges` o expresión CEL (`request.headers`, `request.path`, `origin.region_code`…) |
| **WAF preconfigurado** | Conjuntos de firmas con nivel de sensibilidad y exclusiones por firma/campo |
| **Modo vista previa** | La regla registra lo que haría sin aplicarlo |
| **Rate limiting** | Umbral por clave (IP, cabecera, `XFF-IP`, región…) |
| **Adaptive Protection** | Detección de anomalías L7 y reglas sugeridas |
| **Listas de IP con nombre** | Rangos administrados (por ejemplo, de proveedores de CDN) |

### Evaluación
Las reglas se evalúan por prioridad; la primera que coincide aplica su acción (salvo las de vista previa, que solo registran). La regla por defecto (prioridad máxima) decide el resto.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Tienda pública | Política con WAF preconfigurado y rate limiting |
| Fuerza bruta en login | `throttle` o `rate_based_ban` por IP |
| Solo socios por IP | Allowlist + `deny` por defecto |
| Autenticación de usuarios | **No**: aplicación / API Gateway |
| Tráfico que no pasa por el balanceador | **No** lo ve |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Falso positivo** | Petición legítima bloqueada |
| **Sensibilidad** | Cuántas firmas del conjunto se activan |
| **Exclusión** | Ignorar un campo en una firma concreta |
| **Vista previa** | Probar sin bloquear |
| **Rate-based ban** | Bloquear por un tiempo a quien supera el umbral |

## 5. Cómo se usa
1. Política con WAF en vista previa, rate limiting en login y regla por defecto: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Adjúntala al backend service del balanceador.
3. Audita la política contra el mínimo (WAF, tasa, vista previa) desde [Java](uso-en-java.md).
4. Revisa coincidencias en los registros del balanceador: [`ejemplos/cli/armor.sh`](ejemplos/cli/armor.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Seguridad | `roles/compute.securityAdmin` | — |
| Auditoría | `roles/compute.viewer` | Registros del balanceador |

- El backend debe aceptar tráfico **solo** del balanceador (ingress de Cloud Run interno + balanceador; firewall de rangos de Google).
- Cambios de reglas en código y con revisión.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Vista previa antes de bloquear | Bloquear el primer día |
| Exclusiones precisas | Desactivar un conjunto WAF entero |
| Rate limiting por ruta sensible | Un único límite global |
| Adaptive Protection activo | Esperar a ver el ataque en las facturas |
| Validar entradas también en la app | Confiar solo en el WAF |

## 8. Límites, costos y versiones
- **Costo:** por política y regla al mes y por millón de peticiones evaluadas; Cloud Armor Enterprise con tarifa propia *(verifica)*.
- **Límites** (verifica): reglas por política, expresiones por regla, tamaño del cuerpo inspeccionado.
- **Terraform:** `google_compute_security_policy`, `security_policy` en `google_compute_backend_service`.
- **Java:** `SecurityPoliciesClient` (`google-cloud-compute`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
