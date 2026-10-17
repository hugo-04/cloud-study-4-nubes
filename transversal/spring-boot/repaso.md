# Transversal · Spring Boot · Repaso

## Preguntas
1. ¿Qué hace la auto-configuración y cómo la reemplazas?
2. ¿Por qué `@ConfigurationProperties` con records?
3. ¿Dónde va `@Transactional`?
4. ¿Qué es el problema N+1 y cómo se evita?
5. ¿Por qué `open-in-view: false`?
6. ¿Qué diferencia hay entre liveness y readiness?
7. ¿Qué aportan los hilos virtuales?
8. ¿Qué es ProblemDetail?
9. ¿Qué tipos de prueba conviene combinar?
10. ¿Cómo evitas un cobro doble al reintentar?

## Respuestas
1. Crea beans por defecto según classpath y propiedades; declarando tu propio bean (`@ConditionalOnMissingBean`).
2. Configuración tipada, inmutable y validada en el arranque.
3. En los métodos del servicio, con transacciones cortas.
4. Una consulta por cada elemento de una lista; con `join fetch`, *entity graphs* o proyecciones.
5. Para no ejecutar consultas perezosas fuera del servicio ni alargar conexiones.
6. Liveness: ¿reiniciar?; readiness: ¿enviar tráfico? Las dependencias van en readiness.
7. Bloqueo de I/O barato con el modelo imperativo.
8. Formato estándar de errores HTTP (RFC 9457).
9. Unitarias, *slices* web y de datos, y pocas de punta a punta.
10. Con `Idempotency-Key`, *timeouts* y reintentos acotados.

## Ejercicios
1. Agrega `PUT /v1/pedidos/{id}/cancelar` con bloqueo optimista.
2. Escribe un `@WebMvcTest` que verifique el 400 de validación.
3. Separa la salud de la base en el grupo readiness.
