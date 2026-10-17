# NotebookLM · AWS · Capítulo 05 Ingress y API

**Fuentes a subir:** este `README.md` y los `README.md`, `casos-reales.md` y `uso-en-java.md` de `alb-nlb`, `api-gateway`, `cloudfront-waf` e `ingress-eks`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, sobre cómo entra el tráfico a los microservicios en AWS: ALB y NLB, API Gateway, CloudFront con WAF e Ingress en EKS. Habla solo de AWS; no compares con otras nubes.

Estructura obligatoria:
1. La cadena usuario → CloudFront y WAF → ALB o API Gateway → servicios; qué problema resuelve cada pieza (con las analogías del texto).
2. ALB frente a NLB: capas, listeners, reglas, target groups, health checks, timeouts (idle, keep-alive, deregistration).
3. API Gateway: HTTP API frente a REST API frente a WebSocket, autorizadores JWT, integración con Lambda y VPC link, cuotas.
4. CloudFront y WAF: orígenes, OAC, caché, URLs firmadas, reglas administradas en modo Count y luego Block, límite por IP, cabecera secreta del origen.
5. Ingress en EKS: AWS Load Balancer Controller, modo ip, group.name, TargetGroupBinding, readiness gate, apagado ordenado.
6. Árbol de decisión «quiero…», comparativa y receta ModaLima.
7. Casos reales de cada servicio como historias, con su lección.
8. Java: IP real del cliente, validación de timeouts, firma de URLs, firma SigV4, manejador Lambda de API Gateway, webhook de admisión; versiones imperativas (Spring MVC, Quarkus) y reactivas (WebFlux, Mutiny).
9. Seguridad y errores típicos (502/503/504, origen expuesto, Block sin ensayo).

Reglas: no omitas tablas ni casos; define cada término técnico al usarlo; usa ModaLima y Café Andino como empresas de ejemplo; cierra con 7 puntos de resumen y 5 preguntas de repaso.
```
