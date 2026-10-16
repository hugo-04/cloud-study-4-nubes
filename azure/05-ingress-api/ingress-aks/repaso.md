# Azure · Ingress en AKS · Repaso

## Preguntas de repaso
1. ¿Qué problema resuelve un ingress frente a un `Service` de tipo `LoadBalancer` por servicio?
   - *Una sola entrada L7 con reglas de host/ruta, un certificado y un WAF, en vez de un balanceador por servicio.*
2. ¿Qué diferencia hay entre Ingress y Gateway API?
   - *Gateway API es más expresiva (pesos, cabeceras, reescrituras), separa roles (Gateway vs HTTPRoute) y es la dirección del ecosistema; Ingress depende de anotaciones del controlador.*
3. ¿Qué es un controlador y por qué importa elegirlo con cuidado?
   - *Es el software que implementa las reglas; su soporte, costo y anotaciones condicionan tu migración futura.*
4. ¿Cuándo preferirías Application Gateway for Containers?
   - *En proyectos nuevos en Azure: proxy fuera del clúster, soporte de Gateway API, WAF y pesos de tráfico.*
5. ¿Cómo haces una entrada interna?
   - *Anotación `azure-load-balancer-internal: "true"` (o un AGC/App Gateway privado) y delante APIM o Front Door con Private Link.*
6. ¿Por qué tu API devuelve `http://` detrás de un proxy HTTPS y cómo se arregla?
   - *La app no confía en `X-Forwarded-Proto`; usa `server.forward-headers-strategy=framework` / `quarkus.http.proxy.proxy-address-forwarding`.*
7. ¿Para qué sirve `externalTrafficPolicy: Local`?
   - *Conserva la IP real del cliente y evita saltos, a costa de un reparto menos uniforme.*
8. ¿Cómo evitas que una conexión SSE se corte a los 4 minutos?
   - *Latido más frecuente que el tiempo de inactividad de cada salto.*
9. ¿Qué hace cert-manager y qué desafío eliges para un dominio interno?
   - *Emite y renueva certificados; DNS-01 con Azure DNS, porque HTTP-01 requiere acceso público.*
10. ¿Por qué ocurren errores durante despliegues y cómo los evitas?
    - *El pod sale antes de que el controlador lo retire; `preStop`, readiness y graceful shutdown.*
11. ¿Qué haces para que cambiar de controlador sea barato?
    - *Evitar anotaciones propietarias y preferir Gateway API.*
12. ¿Cuándo pondrías APIM o Front Door delante del ingress?
    - *APIM para políticas de API y consumidores externos; Front Door para entrada global, CDN y WAF.*

## Entrevista
- Diseña la entrada de 15 microservicios de un clúster con una IP y TLS automático.
- ¿Cómo harías un canary 90/10 sin tocar el código?
- Tu rate limit por IP bloquea a todos: ¿qué revisas?
- ¿Cómo migras del NGINX de la comunidad a Gateway API sin cortar el servicio?

## Ejercicio práctico
1. Habilita el add-on de routing y publica `api-pedidos` con un Ingress.
2. Cambia a Gateway API + `HTTPRoute` con pesos 90/10.
3. Provoca un 503 (etiquetas mal puestas) y diagnostícalo con la escalera.
4. Implementa un endpoint SSE con latido y verifica que sobrevive 10 minutos.
