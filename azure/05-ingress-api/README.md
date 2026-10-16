# Azure · 05 Ingress y API

Cómo entra el tráfico a tus servicios. Cuatro piezas que se **combinan** (no compiten): cada una resuelve una capa distinta.

| Pieza | Alcance | Capa | Analogía | La eliges para |
|---|---|---|---|---|
| [Ingress en AKS](ingress-aks/README.md) | El clúster | L7 | Recepcionista del edificio | Publicar muchos servicios del clúster tras una sola puerta (Ingress / Gateway API) |
| [Application Gateway (WAF)](application-gateway/README.md) | Una región, dentro de tu VNet | L7 + WAF | Control de seguridad de la entrada | Entrada regional con WAF y backends privados |
| [Front Door (WAF)](front-door-waf/README.md) | Global (borde de Microsoft) | L7 + WAF + CDN | Recepciones en aeropuertos de todo el mundo | Usuarios en varias regiones, failover, caché |
| [APIM](apim/README.md) | Tu catálogo de APIs | API gateway | Ventanilla única con reglas | Exponer APIs como productos: JWT, cuotas, versiones, portal |

## Qué hace cada una (y qué no)

| Capacidad | Ingress AKS | App Gateway | Front Door | APIM |
|---|---|---|---|---|
| Enrutar por host/ruta | ✔ | ✔ | ✔ | ✔ (por API/operación) |
| TLS | ✔ | ✔ | ✔ (en el borde) | ✔ |
| WAF | Con AGC / delante | ✔ | ✔ | ✘ (delante) |
| Caché | Limitada | ✘ | ✔ | ✔ |
| Failover entre regiones | ✘ | ✘ | ✔ | Premium multi-región |
| Autenticación JWT / cuotas / versiones | ✘ | ✘ | ✘ | ✔ |
| Portal para consumidores | ✘ | ✘ | ✘ | ✔ |
| Acceso privado a backends | ✔ | ✔ | Premium (Private Link) | ✔ (modo interno) |

## Árbol de decisión

```
¿Solo publicas servicios dentro de un clúster AKS?            → Ingress / Gateway API (AGC)
¿Entrada regional, con WAF, a backends en tu VNet?            → Application Gateway
¿Usuarios en varias regiones, CDN, failover?                  → Front Door (+ App Gateway/APIM por región)
¿Terceros o apps que necesitan claves, cuotas, versiones?     → APIM
```

## Patrones que se repiten

| Patrón | Cadena | Cuándo |
|---|---|---|
| **Simple** | Cliente → Ingress AKS → Pods | Un solo clúster, tráfico interno o poco expuesto |
| **Regional con WAF** | Cliente → Application Gateway → App Service / AKS | Una región, requisito de WAF |
| **API empresarial** | Cliente → Front Door o App Gateway → APIM (interno) → AKS interno | APIs a socios y apps móviles |
| **Global activo-activo** | Cliente → Front Door → (App Gateway → backend) por región | Baja latencia y alta disponibilidad |

## Cómo se relacionan con otros capítulos
- [Red · Private Endpoint y DNS](../01-red/private-endpoint-dns/README.md) y [Diagnóstico](../01-red/diagnostico-conectividad/README.md): backends privados y escalera RPDSI.
- [Key Vault](../03-secretos/key-vault/README.md): certificados de los gateways y named values de APIM.
- [Compute](../04-compute/README.md): los backends (App Service, Container Apps, AKS).
- [Managed Identity](../02-iam/managed-identity/README.md): APIM → backend sin secretos.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus), ejemplos (CLI, Terraform, YAML/XML/KQL), troubleshooting, repaso y prompt de NotebookLM.
