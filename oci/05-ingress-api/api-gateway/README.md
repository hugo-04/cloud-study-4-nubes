# Oracle OCI · Ingress y API · API Gateway

Servicio administrado que publica tus APIs: recibe la petición HTTPS, valida el token (JWT) o llama a un autorizador propio, aplica límites de tasa y CORS, transforma cabeceras y enruta a un backend HTTP, una función o una respuesta fija.

## 1. Qué es

**Analogía:** el mostrador de seguridad de un edificio de oficinas. Revisa tu credencial (token), anota a qué piso vas (ruta), te pone una pulsera de visita (cabeceras) y si vienes demasiadas veces en un minuto te pide esperar (límite de tasa). Las oficinas (backends) no tienen que revisar nada de eso otra vez.

```
 App / navegador ──HTTPS──► Gateway (subred pública o privada)
                              └─ Deployment /v1  (especificación: rutas + políticas)
                                   ├─ /catalogo/{resto*} GET ──► HTTP backend (LB interno / OKE)
                                   ├─ /pedidos POST  [JWT + scope] ──► HTTP backend
                                   └─ /miniatura POST ──► Function
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Gateway** | La infraestructura: endpoint `PUBLIC` o `PRIVATE`, subred, certificado propio opcional |
| **Deployment** | Prefijo (`/v1`) + especificación con rutas y políticas; un gateway aloja varios |
| **Ruta** | Ruta + métodos + backend (`HTTP_BACKEND`, `ORACLE_FUNCTIONS_BACKEND`, `STOCK_RESPONSE_BACKEND`, `DYNAMIC_ROUTING_BACKEND`) |
| **Autenticación** | `JWT_AUTHENTICATION` / `TOKEN_AUTHENTICATION` (JWKS remoto o llaves estáticas) o `CUSTOM_AUTHENTICATION` (función autorizadora) |
| **Autorización** | Por ruta: `ANY_OF` alcances, `AUTHENTICATION_ONLY` o `ANONYMOUS` |
| **Políticas** | Límite de tasa, CORS, transformación de cabeceras/consulta, validación de petición, caché de respuestas |
| **Usage plans y suscriptores** | Cuotas por cliente con llaves de cliente (monetización o socios) |
| **Logging** | Registros de acceso y ejecución |

### Recorrido de una petición
1. TLS en el gateway (certificado del servicio o propio).
2. Se elige el deployment por prefijo y la ruta por ruta y método.
3. Políticas en orden: CORS → límite de tasa → autenticación → autorización → validación/transformación.
4. Llamada al backend con los tiempos configurados; el contexto del token puede pasar como cabeceras (`${request.auth[sub]}`).

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| API pública con JWT y límites de tasa | **API Gateway** |
| Exponer funciones como HTTP | **API Gateway** + Functions |
| Cuotas por socio con llaves | Usage plans |
| Solo repartir carga HTTP entre réplicas | [Load Balancer](../load-balancer/README.md) |
| Protección OWASP y bots | [WAF](../waf/README.md) (en el LB delante o en el borde) |
| Tráfico entre microservicios internos | **No**: llamada directa o malla de servicios en OKE |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **JWKS** | URL con las llaves públicas para verificar firmas de JWT |
| **Scope** | Permiso dentro del token (`pedidos.escribir`) |
| **Autorizador propio** | Una función que decide si la petición pasa y devuelve contexto |
| **Comodín de ruta** | `{resto*}` captura el resto de la ruta |
| **Respuesta fija** | Backend que devuelve un cuerpo estático (mantenimiento, *mock*) |

## 5. Cómo se usa
1. Gateway + deployment con JWT, límite de tasa, CORS y rutas: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Si la regla de acceso es propia (llaves de socio, listas), escribe un **autorizador** en Java: [uso en Java](uso-en-java.md).
3. Prueba y diagnostica: [`ejemplos/cli/api-gateway.sh`](ejemplos/cli/api-gateway.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `manage api-gateway-family` | — |
| El gateway (para llamar funciones) | — | `Allow any-user to use functions-family … where ALL {request.principal.type = 'ApiGateway', …}` |
| Clientes | — | JWT/llave validados en el gateway |

- Backends en subred privada; su NSG solo acepta desde la subred del gateway.
- El backend **igual** valida lo crítico (dueño del pedido): el gateway autentica, el dominio autoriza.
- No pases el token completo si no hace falta: reenvía solo `sub` y alcances como cabeceras.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Versionar por deployment (`/v1`, `/v2`) | Romper contratos en el mismo prefijo |
| JWT con `audiences` e `issuers` explícitos | Aceptar cualquier emisor |
| Límite de tasa por IP y cuotas por cliente | API pública sin límites |
| Tiempos de backend menores que los del cliente | *Timeouts* por defecto |
| Caché de JWKS con duración razonable | Descargar JWKS en cada petición |
| Autorizador con caché de resultados | Autorizador lento que consulta la base cada vez |

## 8. Límites, costos y versiones
- **Costo:** por millón de llamadas a la API *(verifica)*; las funciones y backends se cobran aparte.
- **Límites** (verifica): deployments por gateway, rutas por deployment, tamaño de cuerpo, tiempo máximo del backend.
- **Terraform:** `oci_apigateway_gateway`, `oci_apigateway_deployment`, `oci_apigateway_usage_plan`, `oci_apigateway_subscriber`.
- **SDK:** `GatewayClient`, `DeploymentClient` (`oci-java-sdk-apigateway`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
