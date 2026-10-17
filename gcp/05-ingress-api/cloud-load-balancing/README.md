# Google Cloud · Ingress y API · Cloud Load Balancing

Balanceadores administrados y **definidos por software** (no son VMs). El más usado para web/API es el **balanceador de aplicaciones externo global**: una IP anycast única en todo el mundo, TLS en el borde de Google, enrutamiento por host/ruta (URL map) hacia **servicios de backend** (MIG, NEG de GKE, Cloud Run sin servidor, buckets) con chequeos de salud, CDN y Cloud Armor.

## 1. Qué es

**Analogía:** una central de llamadas con un único número internacional. Llames desde donde llames, te atiende la oficina más cercana, que mira «¿a qué departamento?» (host y ruta) y te pasa con alguien disponible (backend sano).

```
 Cliente ─► IP anycast global (forwarding rule :443) ─► proxy HTTPS (certificado administrado)
              └─ URL map
                   ├─ tienda.modalima.example/api/*  ─► backend service "api"  ─► NEG sin servidor (Cloud Run)
                   ├─ tienda.modalima.example/*      ─► backend service "web"  ─► NEG de GKE (pods) + Cloud CDN
                   └─ estaticos.modalima.example     ─► backend bucket (Cloud Storage)
              Cloud Armor (política de seguridad) en los backend services
```

## 2. Cómo funciona por dentro

### Familia de balanceadores
| Tipo | Capa | Alcance | Para |
|---|---|---|---|
| **Aplicación externo global** | 7 | Global (anycast) | Web/API públicas |
| **Aplicación externo regional** | 7 | Regional | Residencia de datos, Envoy regional |
| **Aplicación interno** | 7 | Regional / entre regiones | Microservicios internos |
| **Red de proxy (TCP/SSL)** | 4 | Global/regional | TCP con terminación en proxy |
| **Red de paso (passthrough)** | 4 | Regional | UDP/TCP con IP de origen intacta |

### Piezas (aplicación)
| Pieza | Qué es |
|---|---|
| **Forwarding rule** | IP + puerto + protocolo |
| **Proxy de destino** | HTTP(S); certificados (Certificate Manager o administrados) y políticas SSL |
| **URL map** | Reglas de host y ruta, redirecciones, reescrituras, división de tráfico |
| **Backend service** | Grupo de backends + chequeo de salud + timeout + afinidad + Cloud Armor + CDN + logging |
| **Backends** | MIG, NEG zonal (pods de GKE), NEG sin servidor (Cloud Run/Functions), NEG de Internet, bucket |
| **Health check** | HTTP/HTTPS/HTTP2/gRPC/TCP con intervalo y umbrales |

### Rangos de origen
Los proxies y chequeos de salud llegan desde `130.211.0.0/22` y `35.191.0.0/16` (verifica): tu firewall debe permitirlos hacia los backends.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Tienda web global con TLS y CDN | Aplicación externo global |
| Exponer Cloud Run con dominio propio y Cloud Armor | NEG sin servidor detrás del global |
| Microservicios internos con TLS y rutas | Aplicación interno |
| UDP o IP de cliente intacta | Red de paso |
| JWT, cuotas por cliente | [API Gateway](../api-gateway/README.md) (o detrás del balanceador) |
| WAF | [Cloud Armor](../cloud-armor/README.md) adjunto al backend service |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Anycast** | La misma IP anunciada en muchos lugares |
| **NEG** | Grupo de endpoints (pods, servicios sin servidor) |
| **URL map** | La tabla de «a dónde va cada URL» |
| **Certificado administrado** | Google lo emite y renueva |
| **Connection draining** | Tiempo para terminar conexiones al retirar un backend |

## 5. Cómo se usa
1. Balanceador global HTTPS con certificado administrado, URL map, Cloud Run por NEG y redirección HTTP→HTTPS: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Simula el enrutamiento del URL map real para pruebas de configuración desde [Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/lb.sh`](ejemplos/cli/lb.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Red/plataforma | `roles/compute.loadBalancerAdmin` | — |
| Certificados | `roles/certificatemanager.editor` | — |
| Clientes | — | Tráfico filtrado por Cloud Armor |

- Backends privados: firewall solo desde los rangos de Google.
- Política SSL con TLS 1.2+ y perfil `MODERN`/`RESTRICTED`.
- Ingress de Cloud Run limitado a «interno y balanceador».

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Certificados administrados | Subir certificados a mano que vencen |
| Chequeo a *readiness* liviano | Chequeo a `/` que consulta la base |
| Timeout del backend acorde al servicio | Timeout por defecto con operaciones largas |
| Redirección HTTP→HTTPS | Servir en HTTP |
| Logging con muestreo | Sin registros de acceso |

## 8. Límites, costos y versiones
- **Costo:** por regla de reenvío-hora y por GB procesado; CDN y Cloud Armor aparte *(verifica)*.
- **Límites** (verifica): reglas de host/ruta por URL map, backends por servicio, certificados por proxy.
- **Terraform:** `google_compute_global_address`, `google_compute_global_forwarding_rule`, `google_compute_target_https_proxy`, `google_compute_url_map`, `google_compute_backend_service`, `google_compute_region_network_endpoint_group`, `google_compute_managed_ssl_certificate`.
- **Java:** `UrlMapsClient`, `BackendServicesClient` (`google-cloud-compute`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
