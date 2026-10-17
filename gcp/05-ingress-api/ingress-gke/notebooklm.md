# NotebookLM · Google Cloud · Entrada a GKE con Gateway API e Ingress

**Fuentes a subir:** todos los `.md` de esta carpeta y de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Entrada a GKE con Gateway API e Ingress en Google Cloud, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. Qué es, con la analogía de la portería de un condominio y un diagrama de sus piezas.
2. Cómo funciona por dentro, componente por componente: GatewayClass, Gateway y listeners, HTTPRoute con pesos, NEG con container-native load balancing, HealthCheckPolicy, GCPBackendPolicy, allowedRoutes y ReferenceGrant, Ingress clásico y Service LoadBalancer.
3. Para qué sirve y cuándo NO usarlo.
4. Conceptos clave explicados en palabras simples: container-native load balancing, allowedRoutes, ReferenceGrant, IP reservada, X-Forwarded-For.
5. Seguridad: tabla de identidad, plano de control y plano de datos, y acceso por red privada.
6. Qué hacer y qué NO hacer, límites y costos (con «verifica» en lo que cambia).
7. Los casos reales y el uso desde Java: la IP real del cliente detrás del balanceador de Google y el inventario de reglas con GlobalForwardingRulesClient; Spring MVC y WebFlux, Quarkus imperativo y Mutiny.
8. Troubleshooting en orden y repaso con 3 preguntas.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
