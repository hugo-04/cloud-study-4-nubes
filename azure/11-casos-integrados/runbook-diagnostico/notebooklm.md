# NotebookLM · Azure · Caso integrado · Runbook de diagnóstico

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/` (Terraform de alertas, CLI de triage, consultas KQL, manifiesto de Kubernetes, JSON de la sonda y plantilla de postmortem).

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre cómo gestionar incidentes en una aplicación de microservicios en Azure con un runbook, para un ingeniero Java de microservicios. No compares con otras nubes.

Estructura obligatoria:
1. La analogía de la lista de verificación del piloto; el flujo de seis pasos de un incidente.
2. Roles y severidades; los primeros cinco minutos; la pregunta «qué cambió».
3. La cadena de capas de afuera hacia adentro (Front Door con WAF, API Management, ingreso y AKS, aplicación, dependencias, red privada, identidad, plataforma) y qué mirar en cada una.
4. Los runbooks por síntoma: errores al comprar, lentitud, pedidos sin factura o cola de fallidos, subida de archivos, clics, gasto disparado; con sus tablas de comprobación y mitigación.
5. Las mitigaciones de menor a mayor riesgo.
6. La escalera de diagnóstico RPDSI y la sonda sintética: cómo funciona cada escalón, hipótesis y siguientes pasos.
7. Alertas por síntoma con Terraform, el pod de diagnóstico y los simulacros.
8. Seguridad: permisos de la guardia, acceso de emergencia con caducidad, datos sensibles en incidentes.
9. Qué hacer y qué NO hacer; costos y límites de la observabilidad.
10. Los siete casos reales como historias con su lección y la plantilla de postmortem sin culpables.
11. Código Java: la escalera, el clasificador, la sonda en paralelo con hilos virtuales, las pruebas reales, Spring MVC y WebFlux, Quarkus imperativo y reactivo.
12. Troubleshooting de las propias herramientas.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
