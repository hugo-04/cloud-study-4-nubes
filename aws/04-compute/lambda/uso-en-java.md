# AWS · Lambda · Uso desde Java

Lo que cambia al escribir Java para Lambda: el **handler**, el **arranque** (Init), las **respuestas de fallo parcial** para colas y la **idempotencia**. Se muestran cuatro formas de empaquetarlo: **Java puro** (la de mejor arranque), **Spring Cloud Function**, **Quarkus Amazon Lambda** y el procesamiento **concurrente** de un lote con **Reactor** o **Mutiny**. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56), `aws-lambda-java-core` 1.4.1, `aws-lambda-java-events` 3.16.

> Un handler de Lambda es **una petición/respuesta**, aunque por dentro uses programación reactiva: el runtime espera a que termines (por eso `block`/`await` dentro del handler es correcto aquí, a diferencia de un servidor WebFlux).

## 1. Núcleo común: lotes con fallos parciales e idempotencia

Funciones **puras** (se prueban sin AWS): procesar el lote respetando el orden (FIFO) o de forma independiente, cortar cuando queda poco tiempo, y un decorador de idempotencia.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import com.amazonaws.services.lambda.runtime.events.SQSBatchResponse;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.function.LongSupplier;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;
import software.amazon.awssdk.services.dynamodb.model.AttributeValue;
import software.amazon.awssdk.services.dynamodb.model.ConditionalCheckFailedException;
import software.amazon.awssdk.services.dynamodb.model.DeleteItemRequest;
import software.amazon.awssdk.services.dynamodb.model.PutItemRequest;

record RegistroSqs(String id, String cuerpo) {}

@FunctionalInterface
interface Manejador {
    void procesar(String id, String cuerpo) throws Exception;
}

final class Lote {
    /** Si queda menos tiempo que esto, no se empiezan más mensajes: vuelven a la cola. */
    static final long MARGEN_MS = 3_000;

    private Lote() {}

    /** Colas FIFO: el orden importa. Al primer fallo (o falta de tiempo) ese y TODOS los siguientes se devuelven. */
    static List<String> enOrden(List<RegistroSqs> registros, Manejador m, LongSupplier msRestantes) {
        List<String> fallidos = new ArrayList<>();
        boolean cortar = false;
        for (RegistroSqs r : registros) {
            if (cortar || msRestantes.getAsLong() < MARGEN_MS) {
                fallidos.add(r.id());
                cortar = true;
                continue;
            }
            try {
                m.procesar(r.id(), r.cuerpo());
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                fallidos.add(r.id());
                cortar = true;
            } catch (Exception e) {
                fallidos.add(r.id());
                cortar = true;
            }
        }
        return fallidos;
    }

    /** Colas estándar: cada mensaje por su cuenta; un fallo no afecta a los demás. */
    static List<String> independientes(List<RegistroSqs> registros, Manejador m, LongSupplier msRestantes) {
        List<String> fallidos = new ArrayList<>();
        for (RegistroSqs r : registros) {
            if (msRestantes.getAsLong() < MARGEN_MS) {
                fallidos.add(r.id());
                continue;
            }
            try {
                m.procesar(r.id(), r.cuerpo());
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                fallidos.add(r.id());
            } catch (Exception e) {
                fallidos.add(r.id());
            }
        }
        return fallidos;
    }

    static SQSBatchResponse respuesta(List<String> fallidos) {
        return new SQSBatchResponse(fallidos.stream().map(SQSBatchResponse.BatchItemFailure::new).toList());
    }
}

/** Marca de «ya procesado». La implementación real usa DynamoDB; en pruebas, un mapa. */
interface RegistroIdempotencia {
    boolean primeraVez(String clave);

    void olvidar(String clave);
}

final class IdempotenciaDynamo implements RegistroIdempotencia {
    private final DynamoDbClient ddb;
    private final String tabla;

    IdempotenciaDynamo(DynamoDbClient ddb, String tabla) {
        this.ddb = ddb;
        this.tabla = tabla;
    }

    @Override
    public boolean primeraVez(String clave) {
        try {
            ddb.putItem(PutItemRequest.builder().tableName(tabla)
                    .item(Map.of("pk", AttributeValue.fromS(clave),
                            "ttl", AttributeValue.fromN(Long.toString(System.currentTimeMillis() / 1000 + 86_400))))
                    .conditionExpression("attribute_not_exists(pk)").build());
            return true;
        } catch (ConditionalCheckFailedException e) {
            return false;       // otro intento ya lo registró
        }
    }

    @Override
    public void olvidar(String clave) {
        ddb.deleteItem(DeleteItemRequest.builder().tableName(tabla)
                .key(Map.of("pk", AttributeValue.fromS(clave))).build());
    }
}

final class Idempotente {
    private Idempotente() {}

    /** Decora un manejador: si ya se procesó, no hace nada; si el efecto falla, libera la marca para el reintento. */
    static Manejador de(RegistroIdempotencia registro, Manejador real) {
        return (id, cuerpo) -> {
            if (!registro.primeraVez(id)) return;
            try {
                real.procesar(id, cuerpo);
            } catch (Exception e) {
                registro.olvidar(id);
                throw e;
            }
        };
    }
}
```
Configura la tabla de idempotencia con **TTL** sobre el atributo `ttl` para que se limpie sola.

## 2. Java puro (mejor arranque)
Sin framework: el Init solo carga lo mínimo. Los clientes se crean **una vez**, en campos estáticos.
```java
import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.SQSBatchResponse;
import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import java.util.List;
import software.amazon.awssdk.http.urlconnection.UrlConnectionHttpClient;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.dynamodb.DynamoDbClient;

public class PedidosHandler implements RequestHandler<SQSEvent, SQSBatchResponse> {
    // Init: se ejecuta una vez por entorno (y con SnapStart, antes de la instantánea)
    private static final DynamoDbClient DDB = DynamoDbClient.builder()
            .httpClient(UrlConnectionHttpClient.create())      // más ligero que Apache al arrancar
            .region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1")))
            .build();
    private static final Manejador MANEJADOR = Idempotente.de(
            new IdempotenciaDynamo(DDB, System.getenv().getOrDefault("TABLA_IDEMPOTENCIA", "idempotencia")),
            PedidosHandler::procesarPedido);

    @Override
    public SQSBatchResponse handleRequest(SQSEvent evento, Context contexto) {
        List<RegistroSqs> registros = evento.getRecords().stream()
                .map(m -> new RegistroSqs(m.getMessageId(), m.getBody())).toList();
        List<String> fallidos = Lote.independientes(registros, MANEJADOR, contexto::getRemainingTimeInMillis);
        contexto.getLogger().log("lote=" + registros.size() + " fallidos=" + fallidos.size());   // nunca el cuerpo
        return Lote.respuesta(fallidos);
    }

    static void procesarPedido(String id, String cuerpo) {
        if (!cuerpo.trim().startsWith("{")) {
            throw new IllegalArgumentException("Cuerpo inválido en el mensaje " + id);
        }
        // Aquí: validar, aplicar la regla de negocio y escribir de forma idempotente
    }
}
```
Handler en Terraform: `com.modalima.pedidos.PedidosHandler::handleRequest` (el ejemplo ya tiene SnapStart activado).

## 3. Spring Cloud Function (Spring Boot 4)
El handler de Lambda es `org.springframework.cloud.function.adapter.aws.FunctionInvoker`, y la función se elige con `SPRING_CLOUD_FUNCTION_DEFINITION=procesarPedidos`. Se recibe un `Message` para poder leer el `Context` de Lambda (cabecera `aws-context`). Dependencia: `spring-cloud-function-adapter-aws` (verifica la versión alineada con tu Spring Boot). El arranque es más lento: **usa SnapStart** y reduce autoconfiguraciones.
```java
import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.events.SQSBatchResponse;
import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import java.util.List;
import java.util.function.Function;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.messaging.Message;
import org.springframework.stereotype.Service;

@Service
class ServicioPedidos {
    void procesar(String id, String cuerpo) {
        // regla de negocio idempotente
    }
}

@Configuration
class PedidosFunciones {
    @Bean
    Function<Message<SQSEvent>, SQSBatchResponse> procesarPedidos(ServicioPedidos servicio) {
        return mensaje -> {
            Context contexto = (Context) mensaje.getHeaders().get("aws-context");
            List<RegistroSqs> registros = mensaje.getPayload().getRecords().stream()
                    .map(m -> new RegistroSqs(m.getMessageId(), m.getBody())).toList();
            return Lote.respuesta(Lote.independientes(registros, servicio::procesar,
                    contexto::getRemainingTimeInMillis));
        };
    }
}
```

## 4. Spring con Reactor: el lote en paralelo
Para mensajes independientes con E/S lenta (llamadas HTTP, bases de datos), procesar **varios a la vez** reduce la duración. `block` es correcto aquí: el hilo del handler no es de Netty.
```java
import java.time.Duration;
import java.util.List;
import java.util.function.LongSupplier;
import reactor.core.publisher.Flux;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

final class LoteReactivo {
    private LoteReactivo() {}

    static List<String> independientes(List<RegistroSqs> registros, Manejador m, int concurrencia,
                                       LongSupplier msRestantes) {
        long limite = Math.max(1, msRestantes.getAsLong() - Lote.MARGEN_MS);
        List<String> fallidos = Flux.fromIterable(registros)
                .flatMap(r -> Mono.fromCallable(() -> {
                            if (msRestantes.getAsLong() < Lote.MARGEN_MS) {
                                throw new IllegalStateException("sin tiempo");
                            }
                            m.procesar(r.id(), r.cuerpo());
                            return "";                                  // éxito
                        })
                        .subscribeOn(Schedulers.boundedElastic())
                        .onErrorReturn(r.id()),                         // fallo: devuelvo su id
                        concurrencia)
                .filter(s -> !s.isEmpty())
                .collectList()
                .block(Duration.ofMillis(limite));
        return fallidos == null ? List.of() : fallidos;
    }
}
```

## 5. Quarkus Amazon Lambda (imperativo)
Extensión `quarkus-amazon-lambda`. Se nombra el handler con `@Named` y se indica con `quarkus.lambda.handler=procesarPedidos`. Con **imagen nativa** el arranque baja a milisegundos (verifica la compilación nativa y el runtime `provided.al2023`).
```java
import com.amazonaws.services.lambda.runtime.Context;
import com.amazonaws.services.lambda.runtime.RequestHandler;
import com.amazonaws.services.lambda.runtime.events.SQSBatchResponse;
import com.amazonaws.services.lambda.runtime.events.SQSEvent;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.inject.Named;
import java.util.List;

@ApplicationScoped
class ServicioPedidosQuarkus {
    void procesar(String id, String cuerpo) {
        // regla de negocio idempotente
    }
}

@Named("procesarPedidos")
class PedidosQuarkus implements RequestHandler<SQSEvent, SQSBatchResponse> {
    @Inject
    ServicioPedidosQuarkus servicio;

    @Override
    public SQSBatchResponse handleRequest(SQSEvent evento, Context contexto) {
        List<RegistroSqs> registros = evento.getRecords().stream()
                .map(m -> new RegistroSqs(m.getMessageId(), m.getBody())).toList();
        return Lote.respuesta(Lote.independientes(registros, servicio::procesar, contexto::getRemainingTimeInMillis));
    }
}
```
```properties
# application.properties
quarkus.lambda.handler=procesarPedidos
quarkus.log.level=INFO
```

## 6. Quarkus reactivo (Mutiny): el lote en paralelo
```java
import io.smallrye.mutiny.Multi;
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.CompletionException;
import java.util.function.LongSupplier;

final class LoteMutiny {
    private LoteMutiny() {}

    static List<String> independientes(List<RegistroSqs> registros, Manejador m, int concurrencia,
                                       LongSupplier msRestantes) {
        long limite = Math.max(1, msRestantes.getAsLong() - Lote.MARGEN_MS);
        return Multi.createFrom().iterable(registros)
                .onItem().transformToUni(r -> Uni.createFrom().item(() -> {
                            if (msRestantes.getAsLong() < Lote.MARGEN_MS) {
                                throw new IllegalStateException("sin tiempo");
                            }
                            try {
                                m.procesar(r.id(), r.cuerpo());
                            } catch (Exception e) {
                                throw new CompletionException(e);
                            }
                            return "";                                  // éxito
                        })
                        .runSubscriptionOn(Infrastructure.getDefaultWorkerPool())
                        .onFailure().recoverWithItem(r.id()))           // fallo: devuelvo su id
                .merge(concurrencia)
                .select().where(s -> !s.isEmpty())
                .collect().asList()
                .await().atMost(Duration.ofMillis(limite));
    }
}
```

## 7. Permisos del código
Las llamadas de arriba necesitan en el **rol de ejecución**: `sqs:ReceiveMessage/DeleteMessage/GetQueueAttributes` (para el *event source mapping*), `dynamodb:PutItem/DeleteItem` sobre la tabla de idempotencia, `kms:Decrypt` si la cola está cifrada, y los logs.

## 8. Qué NO hacer desde Java
- ❌ Crear clientes SDK dentro de `handleRequest`.
- ❌ Lanzar una excepción por un solo mensaje malo: devuelve su id en `batchItemFailures`.
- ❌ Procesar mensajes FIFO en paralelo (rompe el orden): usa `enOrden`.
- ❌ Guardar estado de una invocación en campos estáticos.
- ❌ Loguear el cuerpo de los mensajes (pueden llevar datos personales).
- ❌ Cargar Spring completo para una función diminuta sin medir el Init (considera Java puro o Quarkus).
- ❌ Ignorar el tiempo restante: si el timeout te corta a mitad, el lote entero se reprocesa.
