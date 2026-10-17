# Transversal · Patrones de microservicios

Los microservicios cambian un problema (un monolito difícil de cambiar) por otros: **red que falla, datos repartidos, consistencia eventual, operación de muchas piezas**. Estos patrones son las respuestas conocidas a esos problemas. Cada uno trae su porqué, cuándo usarlo y, en los más importantes, código Java que compila.

## 1. Qué es

**Analogía:** una ciudad con barrios especializados (servicios) en vez de un gran almacén único. Los barrios se comunican por calles (red) que a veces se cortan; hacen falta semáforos (*circuit breakers*), correo con acuse de recibo (eventos idempotentes), notarios para acuerdos entre barrios (sagas) y un mapa (descubrimiento) para encontrarse.

```
 Cliente ─► API Gateway / BFF ─► servicio Pedidos ──evento──► broker ──► Pagos, Inventario, Correos
                                    │ base propia                     (cada uno con su base)
                                    └─ outbox → relay              saga: reservar → cobrar → confirmar
                                                                    (si falla: compensar en orden inverso)
 Transversal: trazas distribuidas (id de correlación) · métricas · logs centralizados · configuración externa
```

## 2. El catálogo

### Descomposición y datos
| Patrón | Problema | Solución |
|---|---|---|
| **Por capacidad de negocio / subdominio (DDD)** | ¿Dónde corto los servicios? | Un servicio por *bounded context* con lenguaje propio |
| **Base de datos por servicio** | Acoplamiento por tablas compartidas | Cada servicio es dueño de sus datos; otros acceden por API o eventos |
| **Strangler fig** | Migrar un monolito sin «big bang» | Desviar funcionalidades una a una detrás de un proxy |
| **Anti-corruption layer** | El modelo del legado contamina el nuevo | Traductor (Adapter) en el borde |

### Comunicación
| Patrón | Problema | Solución |
|---|---|---|
| **API Gateway** | Clientes que conocen 20 servicios | Un punto de entrada: enrutamiento, auth, límites |
| **Backend for Frontend (BFF)** | Web y móvil necesitan respuestas distintas | Un gateway por tipo de cliente |
| **Service discovery** | Direcciones que cambian | Registro + DNS del orquestador |
| **Mensajería asíncrona** | Acoplamiento temporal | Eventos/colas con un broker |
| **API composition** | Consultas que cruzan servicios | Un componente consulta y une |
| **Versionado de APIs** | Cambios que rompen clientes | Versionar (`/v2`, cabecera) y deprecar con plazos |
| **Contratos guiados por consumidores** | Romper a un consumidor sin saberlo | Pruebas de contrato en CI |

### Consistencia
| Patrón | Problema | Solución |
|---|---|---|
| **Saga** (orquestada o coreografiada) | Transacción que cruza servicios sin 2PC | Pasos locales + compensaciones |
| **Transactional outbox** | Guardar y publicar sin perder ni inventar | Escribir el evento en la misma transacción y publicar con un relay |
| **Consumidor idempotente / inbox** | Entrega al menos una vez | Registrar el id del evento con clave única |
| **Idempotency key** | Reintentos de clientes que duplican | Clave por operación; repetir devuelve el mismo resultado |
| **CQRS** | Lecturas y escrituras con necesidades distintas | Modelos separados; la vista se proyecta desde eventos |
| **Event sourcing** | Necesitas la historia completa y auditoría | El estado es la suma de eventos inmutables |

### Resiliencia
| Patrón | Problema | Solución |
|---|---|---|
| **Timeout** | Esperas infinitas | Límite de tiempo en toda llamada remota |
| **Retry con backoff y jitter** | Fallos transitorios | Reintentar pocas veces con esperas crecientes y aleatorias |
| **Circuit breaker** | Insistir contra un servicio caído | Abrir el circuito y fallar rápido; probar luego |
| **Bulkhead** | Una dependencia lenta agota todos los hilos | Aislar recursos por dependencia |
| **Rate limiting / load shedding** | Picos que tumban el servicio | Limitar y rechazar temprano (429) |
| **Fallback** | Funcionalidad no crítica caída | Respuesta degradada (caché, valor por defecto) |

### Operación y despliegue
| Patrón | Problema | Solución |
|---|---|---|
| **Health checks (liveness/readiness)** | Enviar tráfico a instancias no listas | Sondas separadas |
| **Configuración externa** | Recompilar por entorno | Variables, archivos montados, servicio de configuración |
| **Trazas distribuidas + id de correlación** | ¿Dónde se pierde el tiempo? | Propagar contexto (W3C Trace Context) |
| **Logs centralizados y métricas** | Diagnosticar en N máquinas | Logs estructurados y métricas RED/USE |
| **Sidecar / service mesh** | Repetir TLS, reintentos, métricas en cada servicio | Proxy junto a cada instancia |
| **Blue/green y canary** | Desplegar con riesgo | Tráfico gradual y reversión rápida |
| **Feature flags** | Separar despliegue de lanzamiento | Activar funcionalidades sin desplegar |

## 3. Para qué sirve y cuándo NO
| Situación | Decisión |
|---|---|
| Equipos independientes con dominios claros y necesidad de escalar distinto | Microservicios con estos patrones |
| Un equipo pequeño y un dominio aún difuso | Monolito modular primero (ver [arquitectura](../arquitectura-y-testing/README.md)) |
| Necesitas transacciones ACID entre todo | Revisa los límites: quizá es un solo servicio |
| Event sourcing «porque sí» | No: complejo; úsalo si la historia es requisito |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Consistencia eventual** | Los datos coinciden «un rato después» |
| **Compensación** | Acción que deshace el efecto de un paso ya hecho |
| **Coreografía / orquestación** | Cada servicio reacciona a eventos / un coordinador dirige |
| **Acoplamiento temporal** | Ambos servicios deben estar arriba a la vez |
| **Radio de impacto** | Cuánto se rompe cuando algo falla |

## 5. Cómo se usa (código)

### Saga orquestada con compensaciones
```java
// (clase reutilizada en los bloques siguientes)
import java.util.ArrayDeque;
import java.util.ArrayList;
import java.util.Deque;
import java.util.List;

/** Orquestador puro: ejecuta pasos en orden; si uno falla, compensa los anteriores en orden inverso. */
final class Saga {

    interface Paso {
        String nombre();

        void ejecutar();

        void compensar();
    }

    record Resultado(boolean completada, List<String> registro) { }

    static Resultado ejecutar(List<Paso> pasos) {
        Deque<Paso> hechos = new ArrayDeque<>();
        List<String> registro = new ArrayList<>();
        for (Paso p : pasos) {
            try {
                p.ejecutar();
                hechos.push(p);
                registro.add("ok:" + p.nombre());
            } catch (RuntimeException e) {
                registro.add("falla:" + p.nombre());
                while (!hechos.isEmpty()) {
                    Paso c = hechos.pop();
                    c.compensar();   // las compensaciones deben ser idempotentes y reintentables
                    registro.add("compensa:" + c.nombre());
                }
                return new Resultado(false, registro);
            }
        }
        return new Resultado(true, registro);
    }

    static Paso paso(String nombre, Runnable hacer, Runnable deshacer) {
        return new Paso() {
            public String nombre() {
                return nombre;
            }

            public void ejecutar() {
                hacer.run();
            }

            public void compensar() {
                deshacer.run();
            }
        };
    }
}
```
En producción el orquestador **persiste el estado** de la saga (paso actual) para retomarla tras un reinicio, y cada paso es un mensaje/llamada idempotente.

### Idempotency key en una API
```java
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Supplier;

/** Repetir la misma clave devuelve el mismo resultado sin volver a ejecutar. En producción: tabla con clave única + TTL. */
final class Idempotencia {
    private final Map<String, Object> resultados = new ConcurrentHashMap<>();

    @SuppressWarnings("unchecked")
    <T> T ejecutar(String clave, Supplier<T> operacion) {
        return (T) resultados.computeIfAbsent(clave, k -> operacion.get());
    }
}
```

### Retry con backoff exponencial y jitter
```java
import java.time.Duration;
import java.util.random.RandomGenerator;

final class Backoff {
    /** «Full jitter»: espera aleatoria entre 0 y min(tope, base·2^intento). Evita que todos reintenten a la vez. */
    static Duration espera(int intento, Duration base, Duration tope, RandomGenerator azar) {
        long max = Math.min(tope.toMillis(), base.toMillis() * (1L << Math.min(intento, 20)));
        return Duration.ofMillis(azar.nextLong(max + 1));
    }
}
```

### Circuit breaker, retry y bulkhead con Resilience4j
```java
import io.github.resilience4j.bulkhead.Bulkhead;
import io.github.resilience4j.bulkhead.BulkheadConfig;
import io.github.resilience4j.circuitbreaker.CircuitBreaker;
import io.github.resilience4j.circuitbreaker.CircuitBreakerConfig;
import io.github.resilience4j.retry.Retry;
import io.github.resilience4j.retry.RetryConfig;
import java.time.Duration;
import java.util.function.Supplier;

final class ClienteResiliente {
    private final CircuitBreaker circuito = CircuitBreaker.of("precios", CircuitBreakerConfig.custom()
        .failureRateThreshold(50)
        .slidingWindowSize(20)
        .waitDurationInOpenState(Duration.ofSeconds(10))
        .build());
    private final Retry reintento = Retry.of("precios", RetryConfig.custom()
        .maxAttempts(3)
        .waitDuration(Duration.ofMillis(200))
        .build());
    private final Bulkhead aislamiento = Bulkhead.of("precios", BulkheadConfig.custom()
        .maxConcurrentCalls(20)
        .build());

    /** Orden: bulkhead (no saturar) → circuito (fallar rápido) → reintento (transitorios) → llamada con timeout propio. */
    long precio(Supplier<Long> llamada, long porDefecto) {
        Supplier<Long> decorada = Bulkhead.decorateSupplier(aislamiento,
            CircuitBreaker.decorateSupplier(circuito, Retry.decorateSupplier(reintento, llamada)));
        try {
            return decorada.get();
        } catch (RuntimeException e) {
            return porDefecto;   // fallback: precio de la caché o «consultar»
        }
    }
}
```

### CQRS: proyección de lectura desde eventos
```java
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/** Vista «resumen de cliente» construida desde eventos; se puede reconstruir releyendo el historial. */
final class ProyeccionClientes {
    sealed interface Evento permits PedidoCreado, PedidoCancelado { String id(); }

    record PedidoCreado(String id, String cliente, long total) implements Evento { }

    record PedidoCancelado(String id, String cliente, long total) implements Evento { }

    record Resumen(int pedidos, long gastado) { }

    private final Map<String, Resumen> vista = new ConcurrentHashMap<>();
    private final Map<String, Boolean> aplicados = new ConcurrentHashMap<>();

    void aplicar(Evento e) {
        if (aplicados.putIfAbsent(e.id() + e.getClass().getSimpleName(), true) != null) {
            return;   // idempotente: el mismo evento dos veces no cambia la vista
        }
        switch (e) {
            case PedidoCreado c -> vista.merge(c.cliente(), new Resumen(1, c.total()),
                (a, b) -> new Resumen(a.pedidos() + 1, a.gastado() + b.gastado()));
            case PedidoCancelado x -> vista.computeIfPresent(x.cliente(),
                (k, a) -> new Resumen(a.pedidos() - 1, a.gastado() - x.total()));
        }
    }

    Resumen de(String cliente) {
        return vista.getOrDefault(cliente, new Resumen(0, 0));
    }
}
```

## 6. Seguridad
| Tema | Práctica |
|---|---|
| Entre servicios | mTLS (malla o librería) e identidades de carga de trabajo |
| Usuarios | Token en el gateway; propagar identidad (JWT) con *scopes* mínimos |
| Datos | Cada servicio expone solo lo necesario; nada de bases compartidas |
| Eventos | Sin datos sensibles; firmados o en canales autenticados |

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Timeout en toda llamada remota | Confiar en los valores por defecto (a veces infinitos) |
| Reintentos en una sola capa, con jitter | Reintentos en cada capa (tormenta) |
| Outbox + consumidor idempotente | Publicar «después del commit» sin más |
| Saga con compensaciones idempotentes | Transacciones distribuidas 2PC |
| Base por servicio | Tablas compartidas entre servicios |
| Trazas con id de correlación | Diagnosticar mirando logs de 15 servicios a mano |
| Monolito modular si el dominio no está claro | Microservicios desde el día uno «por si escalamos» |

## 8. Casos reales
| Historia | Qué pasó | Lección |
|---|---|---|
| El monolito distribuido | ModaLima separó en 12 servicios que compartían la misma base: cada cambio de esquema rompía 5 | Base por servicio y contratos |
| La tormenta de reintentos | Gateway, servicio y cliente reintentaban 3 veces: 27 llamadas por petición a un servicio que ya sufría | Reintentar en un lugar + circuito |
| Stock reservado para siempre | Café Andino cobraba fuera de la saga; si el cobro fallaba, el stock no se liberaba | Compensación de la reserva |
| El cobro duplicado | Un móvil reenviaba el `POST /pagos` al perder señal | Idempotency key |
| La vista desfasada | El panel CQRS mostraba datos viejos sin avisar | Mostrar «actualizado hace X» y medir el retraso |

**Siguiente:** [repaso](repaso.md) · [NotebookLM](notebooklm.md) · [índice transversal](../README.md)
