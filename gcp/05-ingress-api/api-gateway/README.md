# Google Cloud · Ingress y API · API Gateway

Gateway administrado que publica APIs a partir de una especificación **OpenAPI 2.0**: valida **JWT** o **llaves de API**, aplica **cuotas** por consumidor y enruta a backends sin servidor (Cloud Run, Cloud Run functions, App Engine) o HTTP, usando una cuenta de servicio para llamarlos con ID token.

## 1. Qué es

**Analogía:** el mostrador de recepción de un edificio con lista de invitados. Revisa la credencial (JWT o llave), cuenta cuántas veces entra cada visitante (cuota) y lo lleva a la oficina correcta (backend) anunciándolo con su propio pase (ID token de la cuenta del gateway).

```
 Cliente ─► https://tienda-gw-xxxx.uc.gateway.dev
              API "tienda" → configuración (OpenAPI 2.0, inmutable) → Gateway (regional)
                 /v1/catalogo/{sku}  GET   sin auth, cuota por llave de API
                 /v1/pedidos         POST  JWT (emisor + audiencia)  ─► Cloud Run "pedidos" (privado)
              El gateway llama con ID token de su cuenta de servicio (roles/run.invoker)
              Al backend llega X-Apigateway-Api-Userinfo (claims del JWT en base64url)
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **API** | Recurso lógico; crea un servicio administrado (Service Management) |
| **Configuración de API** | La especificación OpenAPI + cuenta de servicio de backend; **inmutable** |
| **Gateway** | Despliegue regional de una configuración con su URL `*.gateway.dev` |
| **`x-google-backend`** | Dirección del backend, `path_translation`, timeout |
| **`securityDefinitions`** | JWT (`x-google-issuer`, `x-google-jwks_uri`, `x-google-audiences`) o llave de API |
| **Cuotas** | `x-google-management` con métricas y límites por consumidor (llave de API) |
| **Cabecera de usuario** | `X-Apigateway-Api-Userinfo`: claims del JWT validado |

### Ciclo de cambios
Nueva especificación → **nueva configuración** → actualizar el gateway para apuntarla (sin editar en caliente).

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| API pública sobre Cloud Run con JWT y cuotas por llave | **API Gateway** |
| Exponer funciones como API REST | **API Gateway** |
| Monetización, portal de desarrolladores, transformaciones complejas | Apigee *(otra línea de producto; verifica)* |
| Solo enrutar y poner WAF | [Load Balancing](../cloud-load-balancing/README.md) + [Cloud Armor](../cloud-armor/README.md) |
| Tráfico interno entre microservicios | **No**: llamadas directas con ID token |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **OpenAPI 2.0** | El contrato de la API (rutas, métodos, seguridad) |
| **Configuración inmutable** | Cada cambio es una versión nueva |
| **Llave de API** | Identifica al consumidor (no lo autentica fuertemente) |
| **JWT** | Token firmado con identidad y alcances |
| **Cuota** | Límite de llamadas por consumidor y periodo |

## 5. Cómo se usa
1. Especificación con JWT, llave de API, cuotas y backend privado: [`ejemplos/openapi/tienda.yaml`](ejemplos/openapi/tienda.yaml).
2. API, configuración y gateway: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
3. En el backend, lee las claims que reenvía el gateway (sin volver a validar la firma, pero sí el negocio) e inventaría gateways desde [Java](uso-en-java.md).
4. CLI: [`ejemplos/cli/gateway.sh`](ejemplos/cli/gateway.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `roles/apigateway.admin` | — |
| Cuenta del gateway | — | `roles/run.invoker` sobre los backends |
| Consumidores | — | Llave de API / JWT |

- Backends privados (solo el gateway los invoca).
- Las llaves de API se restringen a la API concreta (y a IP/referer si aplica).
- El backend confía en la cabecera **solo** si el servicio es privado e invocable únicamente por el gateway.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| JWT con emisor y audiencia | Solo llaves de API para identificar usuarios |
| Cuotas por consumidor | API sin límites |
| Backend privado + ID token | Backend público «porque el gateway valida» |
| Configuraciones versionadas en Git | Editar la especificación a mano en la consola |
| `path_translation` explícito | Sorpresas con rutas reescritas |

## 8. Límites, costos y versiones
- **Costo:** por millón de llamadas con nivel gratuito *(verifica)*.
- **Límites** (verifica): solo OpenAPI 2.0, tamaño de la especificación, regiones disponibles, timeout del backend.
- **Terraform:** `google_api_gateway_api`, `google_api_gateway_api_config`, `google_api_gateway_gateway` (proveedor `google-beta` en algunas versiones *(verifica)*).
- **Java:** `ApiGatewayServiceClient` (`google-cloud-api-gateway`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
