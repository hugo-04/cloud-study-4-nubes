# NotebookLM · AWS · Caso integrado · Runbook de diagnóstico

**Fuentes a subir:** los `.md` de esta carpeta y `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre el caso integrado "runbook de diagnóstico de la tienda" en AWS, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. La analogía de la lista de verificación del piloto y el flujo de seis pasos: declarar, qué cambió, acotar la capa, mitigar, confirmar, postmortem.
2. Roles (comandante, operador, comunicación, escriba) y severidades 1 a 3 con ejemplos de ModaLima.
3. Los primeros cinco minutos y la cadena de capas de afuera hacia adentro (Route 53/CloudFront/WAF, ALB, EKS/ECS, aplicación, dependencias, red privada, identidad, AWS Health); la advertencia del retraso de CloudTrail.
4. Los runbooks por síntoma A a G (errores al comprar, lentitud, pedidos sin factura, sin tráfico, subidas, NAT, gasto) con sus tablas y mitigaciones de menor a mayor riesgo.
5. Alarmas por síntoma: tasa de errores con matemática de métricas, silencio como alarma, p95, antigüedad de cola, DLQ, puertos NAT, filtro de métrica de la sonda, alarmas compuestas; panel de las cuatro señales y consultas guardadas de Logs Insights.
6. Seguridad: tabla identidad / plano de control / plano de datos de la guardia, break-glass y qué NO pegar en el chat.
7. Java: la escalera de diagnóstico y la sonda sintética con hilos virtuales, el triage (minuto en curso ignorado, silencio, cambios sospechosos con CloudTrail, ruido de AssumeRole), Logs Insights asíncrono, informe con caché y degradación; Spring MVC y WebFlux, Quarkus imperativo y Mutiny.
8. Los seis casos reales, troubleshooting del propio runbook y el postmortem sin culpables.

Reglas: no omitas tablas ni casos; define cada término al usarlo; usa ModaLima; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
