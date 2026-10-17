# Transversal · Programación reactiva (Reactor, Mutiny, RxJava)

Programar con **flujos asíncronos de datos** que se componen con operadores y respetan **contrapresión** (*backpressure*: el consumidor dice cuánto puede recibir). Sirve para atender mucho I/O concurrente con pocos hilos. En Java hay tres bibliotecas principales con la misma base (**Reactive Streams**): **Project Reactor** (Spring WebFlux), **SmallRye Mutiny** (Quarkus) y **RxJava 3**. Desde Java 21 los **hilos virtuales** cubren muchos casos con código imperativo; esta guía dice cuándo conviene cada uno.

## 1. Qué es

**Analogía:** una cinta transportadora con estaciones (operadores). Nada se mueve hasta que alguien al final pide piezas (suscripción) y dice cuántas puede recibir (demanda); si una estación falla, la pieza se desvía a la estación de reparación (manejo de errores) sin parar la fábrica.

```
 Publisher ──onSubscribe──► Subscriber
     ▲            request(n)  │        (contrapresión: nunca más de n)
     └────────────────────────┘
 onNext(x)* ─► onComplete  |  onError(e)        (una sola señal terminal)

 Flux.fromIterable(pedidos) ─► filter ─► flatMap(llamada HTTP, concurrencia 8) ─► timeout ─► onErrorResume ─► subscribe
```

## 2. Cómo funciona por dentro

| Concepto | Reactor | Mutiny | RxJava 3 |
|---|---|---|---|
| 0..1 valor | `Mono<T>` | `Uni<T>` | `Single`, `Maybe`, `Completable` |
| 0..N valores | `Flux<T>` | `Multi<T>` | `Flowable` (con contrapresión), `Observable` (sin) |
| Transformar | `map` | `onItem().transform` | `map` |
| Encadenar asíncrono | `flatMap` / `concatMap` | `onItem().transformToUni` / `transformToMulti` | `flatMap` / `concatMap` |
| Error → valor | `onErrorResume` / `onErrorReturn` | `onFailure().recoverWithItem/Uni` | `onErrorResumeNext` / `onErrorReturn` |
| Reintentos | `retryWhen(Retry.backoff(...))` | `onFailure().retry().withBackOff(...).atMost(n)` | `retryWhen(...)` |
| Tiempo límite | `timeout(Duration)` | `ifNoItem().after(...).fail()` | `timeout(...)` |
| Dónde corre | `subscribeOn` / `publishOn` + `Schedulers` | `runSubscriptionOn` / `emitOn` | `subscribeOn` / `observeOn` |
| Pruebas | `StepVerifier` (con tiempo virtual) | `UniAssertSubscriber`, `AssertSubscriber` | `TestObserver`, `TestScheduler` |

### Reglas que explican casi todo
1. **Nada pasa sin suscripción** (flujos fríos): declarar no es ejecutar.
2. **`flatMap` no preserva orden**; `concatMap` sí (uno a la vez); `flatMapSequential` paraleliza y reordena.
3. **No bloquear** en el hilo de eventos: lo bloqueante va a `boundedElastic` / pool de trabajo.
4. **Una señal terminal**: después de `onError` u `onComplete` no hay más.
5. **Contexto** (trazas, usuario) viaja con el flujo (`contextWrite` en Reactor), no en `ThreadLocal`.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Muchas llamadas I/O concurrentes con composición (orquestar 5 servicios) | Reactivo o hilos virtuales con *structured concurrency* |
| *Streaming* (SSE, WebSocket, Kafka) con contrapresión | Reactivo |
| CRUD típico con JDBC/JPA | Imperativo + hilos virtuales |
| Equipo sin experiencia y plazos cortos | Imperativo (depurar reactivo cuesta) |
| Librería clave solo bloqueante | Imperativo, o aislarla en un pool |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Frío / caliente** | Frío: cada suscriptor recibe todo desde el inicio; caliente: se une a lo que está pasando |
| **Contrapresión** | El consumidor limita lo que recibe |
| **Scheduler** | Dónde (qué hilos) se ejecuta cada tramo |
| **Operador** | Paso de la cinta: transforma, filtra, combina |
| **Sink / Emitter** | Puente para emitir desde código imperativo |

## 5. Cómo se usa

### Reactor: orquestar llamadas con concurrencia, *timeout*, reintento y orden
```java
// (clase reutilizada en los bloques siguientes)
import java.time.Duration;
import java.util.List;
import java.util.Map;
import java.util.concurrent.atomic.AtomicInteger;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.util.retry.Retry;

/** Calcula precios de un carrito llamando a un servicio de precios por SKU (simulado). */
class PreciosReactor {

    interface ServicioPrecios {
        Mono<Long> precio(String sku);
    }

    record Linea(String sku, int cantidad) { }

    private final ServicioPrecios precios;

    PreciosReactor(ServicioPrecios precios) {
        this.precios = precios;
    }

    /** Hasta 8 llamadas en paralelo; cada una con timeout de 500 ms y 2 reintentos con backoff; orden original. */
    Mono<Long> total(List<Linea> lineas) {
        return Flux.fromIterable(lineas)
            .flatMapSequential(l -> precios.precio(l.sku())
                .timeout(Duration.ofMillis(500))
                .retryWhen(Retry.backoff(2, Duration.ofMillis(50)))
                .map(p -> p * l.cantidad()), 8)
            .reduce(0L, Long::sum);
    }

    /** Servicio de prueba: falla la primera vez por SKU para ejercitar el reintento. */
    static ServicioPrecios inestable(Map<String, Long> tabla) {
        var intentos = new java.util.concurrent.ConcurrentHashMap<String, AtomicInteger>();
        return sku -> Mono.defer(() -> intentos.computeIfAbsent(sku, k -> new AtomicInteger()).getAndIncrement() == 0
            ? Mono.error(new IllegalStateException("fallo transitorio"))
            : Mono.justOrEmpty(tabla.get(sku)));
    }
}
```

```java
import java.time.Duration;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;
import reactor.core.publisher.Flux;
import reactor.test.StepVerifier;

class PreciosReactorTest {

    @Test
    void sumaConReintentos() {
        var s = new PreciosReactor(PreciosReactor.inestable(Map.of("A", 1000L, "B", 250L)));
        StepVerifier.create(s.total(List.of(new PreciosReactor.Linea("A", 2), new PreciosReactor.Linea("B", 4))))
            .expectNext(3000L)
            .verifyComplete();
    }

    @Test
    void tiempoVirtual() {
        // un flujo de 1 elemento por minuto, probado sin esperar minutos
        StepVerifier.withVirtualTime(() -> Flux.interval(Duration.ofMinutes(1)).take(3))
            .thenAwait(Duration.ofMinutes(3))
            .expectNext(0L, 1L, 2L)
            .verifyComplete();
    }
}
```

### Puente con código bloqueante y contexto
```java
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

class PuenteBloqueante {

    /** JDBC o un SDK bloqueante: fuera del hilo de eventos. */
    Mono<String> buscarCliente(String id) {
        return Mono.fromCallable(() -> consultaJdbc(id)).subscribeOn(Schedulers.boundedElastic());
    }

    /** El id de traza viaja en el contexto del flujo, no en un ThreadLocal. */
    Mono<String> conTraza(String id) {
        return Mono.deferContextual(ctx -> buscarCliente(id).map(c -> ctx.getOrDefault("traza", "-") + ":" + c))
            .contextWrite(c -> c.put("traza", "t-123"));
    }

    private String consultaJdbc(String id) {
        return "cliente-" + id;
    }
}
```

### Mutiny (Quarkus)
```java
import io.smallrye.mutiny.Multi;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import java.time.Duration;
import java.util.List;

class PreciosMutiny {

    interface ServicioPrecios {
        Uni<Long> precio(String sku);
    }

    private final ServicioPrecios precios;

    PreciosMutiny(ServicioPrecios precios) {
        this.precios = precios;
    }

    Uni<Long> total(List<String> skus) {
        return Multi.createFrom().iterable(skus)
            .onItem().transformToUniAndConcatenate(sku -> precios.precio(sku)
                .ifNoItem().after(Duration.ofMillis(500)).fail()
                .onFailure().retry().withBackOff(Duration.ofMillis(50)).atMost(2))
            .collect().asList()
            .onItem().transform(l -> l.stream().mapToLong(Long::longValue).sum());
    }

    Uni<String> bloqueante(String id) {
        return Uni.createFrom().item(() -> "cliente-" + id).runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```

### RxJava 3
```java
import io.reactivex.rxjava3.core.BackpressureStrategy;
import io.reactivex.rxjava3.core.Flowable;
import io.reactivex.rxjava3.core.Single;
import io.reactivex.rxjava3.schedulers.Schedulers;
import java.util.List;
import java.util.concurrent.TimeUnit;

class PreciosRx {

    interface ServicioPrecios {
        Single<Long> precio(String sku);
    }

    Single<Long> total(ServicioPrecios s, List<String> skus) {
        return Flowable.fromIterable(skus)
            .concatMapSingle(sku -> s.precio(sku).timeout(500, TimeUnit.MILLISECONDS).retry(2))
            .reduce(0L, Long::sum);
    }

    /** Fuente rápida con consumidor lento: se descartan los más viejos en vez de reventar memoria. */
    Flowable<Long> eventos(Flowable<Long> rapida) {
        return rapida.onBackpressureLatest().observeOn(Schedulers.computation(), false, 64);
    }

    Flowable<Integer> desdeEmisor() {
        return Flowable.create(e -> {
            for (int i = 0; i < 3; i++) {
                e.onNext(i);
            }
            e.onComplete();
        }, BackpressureStrategy.BUFFER);
    }
}
```

## 6. Seguridad y operación
| Tema | Práctica |
|---|---|
| Recursos | Límites de concurrencia en `flatMap` (no infinito) y *timeouts* en todo |
| Memoria | Contrapresión o políticas de descarte en fuentes rápidas |
| Trazas | Propagación de contexto (Micrometer Context Propagation) |
| Errores | Nunca tragarlos sin registrar; señal terminal clara |

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| `concatMap` / `flatMapSequential` cuando importa el orden | Suponer que `flatMap` ordena |
| Bloqueante en `boundedElastic` o pool de trabajo | `block()` dentro de un flujo |
| Concurrencia explícita en `flatMap` | `flatMap` sin límite contra un servicio externo |
| Probar con `StepVerifier` y tiempo virtual | `Thread.sleep` en las pruebas |
| `subscribe` solo en el borde (el framework lo hace) | `subscribe` anidados dentro de operadores |
| Hilos virtuales para CRUD bloqueante | Volver reactivo un servicio simple «por moda» |

## 8. Casos reales
| Historia | Qué pasó | Lección |
|---|---|---|
| El carrito desordenado | Las líneas del carrito de ModaLima salían en orden aleatorio | `flatMapSequential` o `concatMap` |
| El servicio de precios tumbado | `flatMap` sin límite lanzó 3 000 llamadas simultáneas | Concurrencia 8–16 y *timeouts* |
| El event loop congelado | Un `block()` en un filtro de WebFlux dejó la API sin responder | Nunca bloquear en el hilo de eventos |
| La traza perdida | Los logs de Café Andino no tenían id de traza tras un `flatMap` | Contexto del flujo, no `ThreadLocal` |
| Reactivo innecesario | Un CRUD reactivo costaba el doble de mantener | Hilos virtuales para lo simple |

**Siguiente:** [repaso](repaso.md) · [NotebookLM](notebooklm.md) · [índice transversal](../README.md)
