# NotebookLM · Azure · Application Gateway

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/`.

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure Application Gateway con WAF, para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes.

Estructura obligatoria:
1. Qué es, con la analogía del control de seguridad de la entrada de un edificio; capa 7, regional, dentro de la VNet.
2. Cómo funciona por dentro: frontend IP, listener, WAF, regla, configuración HTTP, sonda y pool. Dibuja el diagrama.
3. La cabecera Host: opciones, síntomas y cómo se resuelve; las cabeceras que añade el gateway (X-Forwarded-For con puerto, X-Original-Host, X-AppGW-Trace-Id).
4. Sondas de salud: cómo diseñarlas y por qué un 502 casi siempre es backend no sano.
5. TLS: terminación, extremo a extremo, certificados desde Key Vault sin versión con identidad administrada.
6. Red: subred dedicada, reglas obligatorias del NSG (GatewayManager 65200-65535), DNS y backends privados.
7. WAF: modos Detection y Prevention, puntaje de anomalía, reglas personalizadas, exclusiones, falsos positivos y logs.
8. Autoescala, zonas, costos y métricas.
9. Los 10 casos reales como historias con su lección.
10. Código Java: normalizar X-Forwarded-For, correlación con X-AppGW-Trace-Id, endpoint de sonda, patrón asíncrono 202 para tareas largas, TLS extremo a extremo en Spring y Quarkus.
11. Ejemplos de Terraform (gateway completo con WAF), CLI y consultas KQL.
12. Cuándo NO usar Application Gateway, qué hacer, qué NO hacer, y la tabla de troubleshooting con la secuencia para un 5xx.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
