# NotebookLM · Azure · API Management (APIM)

**Fuentes a subir:** todos los `.md` de esta carpeta y los archivos de `ejemplos/` (xml, openapi, terraform, cli, kql).

```
Crea un video largo y detallado en español latinoamericano, didáctico y cercano, solo sobre Azure API Management, para un ingeniero Java de microservicios que quiere dominarlo de inicio a fin. No compares con otras nubes.

Estructura obligatoria:
1. Qué es, con la analogía de la ventanilla de atención a empresas de un banco; gateway, plano de administración y portal.
2. Cómo funciona por dentro: el flujo de una petición (resolución, suscripción, inbound, backend, outbound, on-error). Dibuja el diagrama.
3. El modelo de objetos: API, operación, producto, suscripción, grupo, política, fragmento, named value, backend, versión, revisión.
4. Tiers: Consumption, Developer, Basic, Standard, Premium y v2; cuándo cada uno.
5. El motor de políticas: ámbitos, herencia y <base />, expresiones C#, familias de políticas (autenticación, límites, transformación, validación, flujo, caché, observabilidad).
6. Autenticación: clave de suscripción vs JWT vs mTLS vs identidad administrada; el patrón recomendado.
7. Versiones y revisiones, y cómo retirar una versión sin romper a nadie.
8. Red: público, VNet externa e interna, Private Endpoint, gateway autoalojado; NSG obligatorio (3443, 6390), DNS y subred dedicada; el flujo de extremo a extremo con Front Door o Application Gateway.
9. Observabilidad: Application Insights, GatewayLogs, rastreo, métricas de capacidad.
10. Los 12 casos reales como historias con su lección.
11. Código Java: validar el JWT también en el backend (Spring y Quarkus), leer cabeceras que APIM añade, cliente con clave y token, reintentos que respetan Retry-After (RestClient y WebClient), Idempotency-Key, errores problem+json, imperativo y reactivo.
12. Ejemplos: políticas XML completas, OpenAPI, Terraform, CLI y KQL; cuándo NO usar APIM, qué hacer, qué NO hacer, costos y la tabla de troubleshooting con cómo depurar una política.

Reglas: no omitas tablas, comandos ni casos; define cada término la primera vez; usa ejemplos de ModaLima y Café Andino; cierra con 5 puntos de resumen y 3 preguntas de repaso.
```
