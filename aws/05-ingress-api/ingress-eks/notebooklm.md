# NotebookLM · AWS · Ingress en EKS (AWS Load Balancer Controller)

**Fuentes a subir:** los `.md` de esta carpeta y `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Ingress en Amazon EKS con el AWS Load Balancer Controller, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. La analogía del conserje inteligente y el flujo de kubectl apply a ALB.
2. Controlador, Ingress, Service LoadBalancer, modo ip, group.name, anotaciones, TargetGroupBinding, readiness gate, etiquetas de subred, Pod Identity; alternativas (Auto Mode, Gateway API, estado de ingress-nginx).
3. Cuándo sí y cuándo no.
4. Seguridad: quién puede publicar, scheme interno, TLS, WAF.
5. Qué hacer y qué no; costos.
6. Los seis casos reales como historias con su lección.
7. Java: apagado coordinado con el balanceador (SIGTERM, preStop, deregistration), readiness en Spring MVC y WebFlux y en Quarkus (imperativo y Mutiny), cálculo de la secuencia de apagado.
8. Troubleshooting con kubectl.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
