# Oracle OCI · Mensajería · Events · Repaso

## Preguntas
1. ¿Qué emite eventos en OCI?
2. ¿Cómo se forma un `eventType`?
3. ¿Qué destinos puede tener una regla?
4. ¿Qué compartimentos ve una regla?
5. ¿Cómo se combinan valores y campos en la condición?
6. ¿Sirve Events para eventos de negocio de tu app?
7. ¿Qué garantía de entrega hay?
8. ¿Qué evento vigilarías primero en seguridad?
9. ¿Qué diferencia hay con Audit?
10. ¿Cuánto cuesta Events?

## Respuestas
1. Los servicios de OCI al cambiar recursos.
2. `com.oraclecloud.<servicio>.<acción>`.
3. Notifications, Functions y Streaming.
4. El suyo y sus descendientes.
5. Valores de una lista con O; campos distintos con Y.
6. No; usa Queue, Notifications o Streaming.
7. Al menos una vez, sin orden.
8. Cambios de políticas IAM.
9. Audit registra todas las llamadas a la API; Events emite tipos publicados para reaccionar.
10. No tiene cargo propio; pagas los destinos.

## Ejercicios
1. Escribe la condición para cambios en listas de seguridad y NSG de producción.
2. Diseña la función que limpia DNS al terminar instancias.
3. Decide qué eventos van a correo y cuáles a Streaming para ModaLima.
