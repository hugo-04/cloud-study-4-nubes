# AWS · API Gateway · Repaso

## Preguntas
1. ¿Diferencia entre HTTP API y REST API?
   - *HTTP API es más barata y simple (JWT nativo); REST suma claves de API, planes de uso, caché, transformación y WAF.*
2. ¿Para qué sirve un VPC Link?
   - *Para llegar a un ALB/NLB privado sin exponerlo a Internet.*
3. ¿Qué tipos de autorizador existen?
   - *JWT, IAM (SigV4), Lambda y Cognito (REST).*
4. ¿Qué haces con tareas de más de 30 s?
   - *Responder 202 y procesarlas de forma asíncrona.*
5. ¿Por qué cachear el autorizador Lambda?
   - *Evita invocarlo y consultar la base en cada petición.*
6. ¿Qué es el payload format 2.0?
   - *La estructura del evento que HTTP API entrega a Lambda.*
7. ¿Por qué validar de nuevo en el backend?
   - *Defensa en profundidad: el gateway puede saltarse por error de red.*
8. ¿Cómo subes archivos grandes?
   - *Con URL prefirmada de S3, no por la API.*
9. ¿Cuándo preferir un ALB a API Gateway?
   - *Alto volumen constante sin necesidad de gestión de APIs.*
10. ¿Qué significa 429?
    - *Throttling: demasiadas peticiones; el cliente debe reintentar con espera.*

## Ejercicios
1. Diseña rutas y autorizador para la API pública de Pedidos.
2. Define el throttling por ruta (login, búsqueda, lectura).
3. Convierte un endpoint de informe de 40 s en un flujo asíncrono.
4. Escribe la política de recurso de la función Lambda para API Gateway.

## Autoevaluación
- [ ] Sé elegir HTTP API o REST API.
- [ ] Sé configurar JWT, VPC Link y throttling.
- [ ] Sé diagnosticar 401/403/429/5XX.
- [ ] Sé aplicar defensa en profundidad.
