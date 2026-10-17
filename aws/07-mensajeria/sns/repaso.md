# AWS · SNS · Repaso

## Preguntas
1. ¿Qué es un tópico y qué es una suscripción?
   - *El canal donde publicas / quién escucha y por qué protocolo.*
2. ¿Cuál es el patrón clásico SNS + SQS?
   - *Fan-out: un tópico con una cola por suscriptor.*
3. ¿Qué hace una política de filtro?
   - *Entrega a cada suscriptor solo los mensajes que cumplen sus reglas.*
4. ¿Qué es la entrega cruda?
   - *El suscriptor recibe el mensaje tal cual, sin el sobre JSON de SNS.*
5. ¿Para qué una DLQ de suscripción?
   - *Guardar lo que SNS no pudo entregar a ese suscriptor.*
6. ¿Qué diferencia hay entre SNS estándar y FIFO?
   - *FIFO garantiza orden por grupo y deduplicación; solo entrega a colas SQS.*
7. ¿Por qué un filtro numérico puede fallar?
   - *El atributo se publicó como String y no como Number.*
8. ¿Cuándo es mejor EventBridge?
   - *Enrutamiento complejo por contenido, SaaS, archivo y reproducción.*
9. ¿Qué garantía de entrega ofrece SNS estándar?
   - *Al menos una vez.*
10. ¿Por qué poner una cola entre SNS y una Lambda?
    - *Para absorber picos, reintentar y tener DLQ visible.*

## Ejercicios
1. Escribe la política de filtro para «total mayor a 100 y envío a domicilio».
2. Diseña el fan-out de «OrdenCreada» a facturación, logística y analítica.
3. Escribe la política de cola que acepta solo de tu tópico.
4. Decide estándar o FIFO para «cambios de estado de pedido» y justifícalo.

## Autoevaluación
- [ ] Sé crear tópico, colas suscritas, filtros y DLQ.
- [ ] Sé publicar atributos tipados.
- [ ] Sé desempaquetar el sobre cuando haga falta.
- [ ] Sé diagnosticar «no llega nada a la cola».
