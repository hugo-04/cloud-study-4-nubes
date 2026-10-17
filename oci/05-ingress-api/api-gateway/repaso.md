# Oracle OCI · Ingress y API · API Gateway · Repaso

## Preguntas
1. ¿Qué diferencia hay entre gateway y deployment?
2. ¿Qué tipos de backend existen?
3. ¿Qué valida la autenticación JWT?
4. ¿Qué devuelve un autorizador propio?
5. ¿Qué responde el gateway al superar el límite de tasa?
6. ¿Cómo versionas una API?
7. ¿Qué política necesita el gateway para invocar funciones?
8. ¿Por qué el backend debe seguir autorizando?
9. ¿Qué son los usage plans?
10. ¿Dónde va el backend en la red?

## Respuestas
1. El gateway es la infraestructura; el deployment, la especificación publicada bajo un prefijo.
2. HTTP, Functions, respuesta fija y enrutamiento dinámico.
3. Firma (JWKS o llave), emisor, audiencia, expiración y desfase de reloj.
4. Si está activo, el principal, los alcances, la expiración y un contexto opcional.
5. `429 Too Many Requests`.
6. Un deployment por versión (`/v1`, `/v2`).
7. `use functions-family` con `request.principal.type = 'ApiGateway'`.
8. Porque las reglas de negocio (dueño del recurso) solo las conoce el dominio.
9. Cuotas y límites por cliente con llaves de suscriptor.
10. En subred privada, accesible solo desde la subred del gateway.

## Ejercicios
1. Diseña las rutas y alcances de la API de pedidos de ModaLima.
2. Escribe la respuesta del autorizador para una llave de socio válida con 15 minutos de caché.
3. Convierte el reporte de ventas en un flujo asíncrono 202 + estado.
