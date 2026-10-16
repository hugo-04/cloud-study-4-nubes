# Azure · APIM · Repaso

## Preguntas de repaso
1. ¿Qué tres componentes tiene APIM?
   - *Gateway (plano de datos), plano de administración y portal de desarrolladores.*
2. ¿Qué hace cada sección de una política?
   - *`inbound`: antes del backend (autenticar, limitar, transformar); `backend`: la llamada; `outbound`: la respuesta; `on-error`: manejar fallos.*
3. ¿Qué hace `<base />` y qué pasa si lo omites?
   - *Hereda la política del ámbito superior; sin él pierdes políticas globales/de producto.*
4. ¿Clave de suscripción o JWT para seguridad?
   - *La clave identifica y mide; la seguridad real es el JWT (más mTLS/identidad hacia el backend).*
5. ¿Diferencia entre versión y revisión?
   - *Versión: contrato público con ruptura; revisión: cambio interno compatible que se promueve.*
6. ¿Límite de tasa vs cuota?
   - *Tasa: llamadas por ventana corta; cuota: total por un periodo largo.*
7. ¿Cómo llama APIM al backend sin secretos?
   - *`authentication-managed-identity` con la audiencia del backend y el rol correspondiente.*
8. ¿Cómo se despliega APIM en una red privada?
   - *Inyección en VNet modo interno (o Private Endpoint en tiers v2) con Application Gateway/Front Door delante; subred dedicada y NSG con 3443/6390.*
9. ¿Por qué un `rate-limit-by-key` por IP falla detrás de un gateway?
   - *Todas las peticiones llegan con la IP del gateway; usa suscripción, JWT o `X-Forwarded-For`.*
10. Diferencia entre 502 y 504 en APIM.
    - *502: no se pudo hablar con el backend (red/TLS); 504: el backend no respondió a tiempo.*
11. ¿Cómo evitas que un reintento duplique un `POST`?
    - *No reintentar no idempotentes, o `Idempotency-Key` con deduplicación en el backend.*
12. ¿Qué es el soft-delete de APIM y qué provoca?
    - *Un APIM eliminado queda reservado unos días: bloquea reutilizar el nombre hasta purgarlo.*

## Entrevista
- Diseña la entrada de una API pública con WAF, APIM interno y AKS privado.
- ¿Cómo publicas la v2 sin romper la v1? ¿Cómo comunicas el retiro?
- Tu APIM responde 500 en una operación: ¿cómo lo depuras?
- ¿Qué pondrías en APIM y qué en el microservicio?
- ¿Cómo gestionas APIM como código en tres entornos?

## Ejercicio práctico
1. Importa [pedidos.json](ejemplos/openapi/pedidos.json) y aplica la política [10-api-policy.xml](ejemplos/xml/10-api-policy.xml).
2. Crea un producto con cuota y una suscripción; prueba el 429.
3. Cambia el esquema de versión a cabecera y publica `v2`.
4. Provoca un 401 (audiencia incorrecta) y corrígelo decodificando el token.
