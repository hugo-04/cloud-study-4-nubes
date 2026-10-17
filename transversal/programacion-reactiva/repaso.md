# Transversal · Programación reactiva · Repaso

## Preguntas
1. ¿Qué es la contrapresión?
2. ¿Qué pasa si declaras un `Flux` y nadie se suscribe?
3. ¿Diferencias entre `flatMap`, `concatMap` y `flatMapSequential`?
4. ¿Dónde ejecutas una llamada JDBC en un flujo reactivo?
5. ¿Por qué `block()` dentro de un flujo es un error?
6. ¿Cómo viaja el id de traza en Reactor?
7. ¿Equivalentes de `Mono` y `Flux` en Mutiny y RxJava?
8. ¿Cómo pruebas un flujo con retrasos de minutos?
9. ¿Cuándo prefieres hilos virtuales?
10. ¿Qué diferencia hay entre `Flowable` y `Observable`?

## Respuestas
1. El consumidor pide cuántos elementos puede recibir.
2. Nada: los flujos fríos no se ejecutan sin suscripción.
3. `flatMap` concurrente sin orden; `concatMap` secuencial y ordenado; `flatMapSequential` concurrente con orden de salida.
4. En `Schedulers.boundedElastic()` (o el pool de trabajo).
5. Bloquea un hilo de eventos y puede congelar el servidor.
6. En el `Context` del flujo (`contextWrite` / `deferContextual`).
7. `Uni`/`Multi`; `Single`/`Maybe`/`Completable` y `Flowable`/`Observable`.
8. Con `StepVerifier.withVirtualTime`.
9. En CRUD y lógica imperativa con I/O bloqueante.
10. `Flowable` soporta contrapresión; `Observable` no.

## Ejercicios
1. Agrega un `Retry.backoff` con *jitter* y un tope total de 2 s.
2. Convierte `PreciosReactor.total` a hilos virtuales con `StructuredTaskScope` (verifica estado de la API).
3. Escribe una prueba de `PreciosMutiny` con `UniAssertSubscriber`.
