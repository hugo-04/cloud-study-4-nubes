# Oracle OCI · Compute · Functions · Repaso

## Preguntas
1. ¿Qué es una aplicación de Functions?
2. ¿Qué es el arranque en frío y cómo se mitiga?
3. ¿Diferencia entre `Sync` y `Detached`?
4. ¿Por qué hay que ser idempotente?
5. ¿Cómo obtiene credenciales la función?
6. ¿Cuál es el límite de tiempo aproximado?
7. ¿Qué dispara funciones desde otros servicios?
8. ¿Cuándo es mala idea una función?
9. ¿Qué política necesita quien invoca?
10. ¿Por qué un endpoint por función?

## Respuestas
1. Un agrupador de funciones con red, configuración y registros.
2. Demora de la primera invocación; concurrencia aprovisionada y arranque ligero.
3. Esperar la respuesta o disparar sin esperar.
4. Los eventos y los reintentos pueden repetirse.
5. Con resource principal.
6. Hasta unos 300 segundos *(verifica)*.
7. Events, API Gateway, Notifications, Service Connector.
8. Trabajo largo, estado local o latencia estricta constante.
9. `use fn-invocation` sobre la función.
10. La invocación se dirige al endpoint de esa función.

## Ejercicios
1. Diseña el nombre determinista del resultado de una miniatura.
2. Calcula el costo de 1 millón de invocaciones de 200 ms con 256 MB.
3. Decide qué cadena de pasos va en una función y cuál en mensajería.
