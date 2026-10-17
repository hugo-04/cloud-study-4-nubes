# AWS · MSK · Uso desde Java

MSK habla el protocolo Kafka, así que usas los clientes de siempre (`kafka-clients`, Spring for Apache Kafka, reactor-kafka, SmallRye Reactive Messaging). Lo propio de MSK está en cuatro piezas que aquí se dejan como código reutilizable: **propiedades de cliente con IAM**, **validador de nombres de tópico**, **planificador de particiones y almacenamiento** y **creación idempotente de tópicos**. Versiones: Java 21, Spring Boot 4.1 (Spring for Apache Kafka), Quarkus 3.40 (`quarkus-messaging-kafka`), `software.amazon.msk:aws-msk-iam-auth` 2.3.x. Los conceptos de Kafka (particiones, grupos, offsets) están en el módulo transversal [Kafka](../../../transversal/kafka/README.md).

## 1. Configuración
```yaml
# Spring Boot (application.yml)
app:
  msk-bootstrap: ${MSK_BOOTSTRAP}          # BootstrapBrokerStringSaslIam (puerto 9098)
spring:
  kafka:
    bootstrap-servers: ${MSK_BOOTSTRAP}
    properties:
      security.protocol: SASL_SSL
      sasl.mechanism: AWS_MSK_IAM
      sasl.jaas.config: software.amazon.msk.auth.iam.IAMLoginModule required;
      sasl.client.callback.handler.class: software.amazon.msk.auth.iam.IAMClientCallbackHandler
    producer:
      acks: all
      key-serializer: org.apache.kafka.common.serialization.StringSerializer
      value-serializer: org.apache.kafka.common.serialization.StringSerializer
      properties:
        enable.idempotence: true
        compression.type: lz4
        linger.ms: 20
    consumer:
      group-id: facturacion
      enable-auto-commit: false
      auto-offset-reset: earliest
      max-poll-records: 100
      key-deserializer: org.apache.kafka.common.serialization.StringDeserializer
      value-deserializer: org.apache.kafka.common.serialization.StringDeserializer
    listener:
      ack-mode: manual
```
```properties
# Quarkus (application.properties) — el prefijo kafka. aplica a todos los canales
kafka.bootstrap.servers=${MSK_BOOTSTRAP}
kafka.security.protocol=SASL_SSL
kafka.sasl.mechanism=AWS_MSK_IAM
kafka.sasl.jaas.config=software.amazon.msk.auth.iam.IAMLoginModule required;
kafka.sasl.client.callback.handler.class=software.amazon.msk.auth.iam.IAMClientCallbackHandler

mp.messaging.outgoing.pedidos-out.connector=smallrye-kafka
mp.messaging.outgoing.pedidos-out.topic=pedidos.orden.creada.v1
mp.messaging.outgoing.pedidos-out.acks=all
mp.messaging.outgoing.pedidos-out.enable.idempotence=true
mp.messaging.outgoing.pedidos-out.key.serializer=org.apache.kafka.common.serialization.StringSerializer
mp.messaging.outgoing.pedidos-out.value.serializer=org.apache.kafka.common.serialization.StringSerializer

mp.messaging.incoming.pedidos-in.connector=smallrye-kafka
mp.messaging.incoming.pedidos-in.topic=pedidos.orden.creada.v1
mp.messaging.incoming.pedidos-in.group.id=facturacion
mp.messaging.incoming.pedidos-in.auto.offset.reset=earliest
mp.messaging.incoming.pedidos-in.key.deserializer=org.apache.kafka.common.serialization.StringDeserializer
mp.messaging.incoming.pedidos-in.value.deserializer=org.apache.kafka.common.serialization.StringDeserializer
mp.messaging.incoming.pedidos-in.failure-strategy=dead-letter-queue
mp.messaging.incoming.pedidos-in.dead-letter-queue.topic=pedidos.orden.creada.v1.dlq
```
> Las credenciales salen de la cadena por defecto del SDK (identidad de pod en EKS, rol de tarea en ECS, rol de instancia). No pongas claves en los archivos.

## 2. Núcleo común

### 2.1 Nombres de tópico
Reglas de Kafka (obligatorias) más una convención `dominio.entidad.evento.vN` (con sufijo opcional `.dlq`). Además detecta nombres que **colisionan** en métricas por diferir solo en `.` frente a `_`.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

public final class NombresTopico {
    private static final Pattern LEGAL = Pattern.compile("[a-zA-Z0-9._-]+");
    private static final Pattern CONVENCION = Pattern.compile("[a-z][a-z0-9-]*(\\.[a-z][a-z0-9-]*){2,}\\.v[0-9]+(\\.dlq)?");

    private NombresTopico() {}

    /** Lista vacía = nombre válido. */
    public static List<String> problemas(String nombre) {
        List<String> p = new ArrayList<>();
        if (nombre == null || nombre.isEmpty()) {
            p.add("vacío");
            return p;
        }
        if (nombre.equals(".") || nombre.equals("..")) {
            p.add("no puede ser . ni ..");
        }
        if (nombre.length() > 249) {
            p.add("más de 249 caracteres");
        }
        if (!LEGAL.matcher(nombre).matches()) {
            p.add("solo letras, números, '.', '_' y '-'");
        }
        if (nombre.startsWith("__")) {
            p.add("el prefijo '__' está reservado a tópicos internos");
        }
        if (!CONVENCION.matcher(nombre).matches()) {
            p.add("no sigue la convención dominio.entidad.evento.vN (minúsculas)");
        }
        return p;
    }

    public static boolean colisionan(String a, String b) {
        return !a.equals(b) && a.replace('.', '_').equals(b.replace('.', '_'));
    }
}
```

### 2.2 Planificador de particiones y almacenamiento
Responde dos preguntas antes de crear un tópico: **¿cuántas particiones?** (las que exijan la escritura y la lectura, con margen) y **¿cuánto disco?** (rendimiento × retención × réplicas). Los rendimientos por partición y por consumidor son datos que mides en tu carga.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.List;

public final class PlanificadorMsk {
    public record Plan(int particiones, double almacenamientoTotalGiB, double almacenamientoPorBrokerGiB,
                       int minInsyncReplicas, List<String> avisos) {}

    private PlanificadorMsk() {}

    /**
     * @param entradaMbs                 MB/s que entran al tópico en el pico
     * @param mbsPorParticionEscritura   MB/s que soporta una partición (mídelo)
     * @param mbsPorConsumidor           MB/s que procesa una instancia consumidora (mídelo)
     * @param margen                     crecimiento esperado (1.3 = 30 %)
     */
    public static Plan calcular(double entradaMbs, double mbsPorParticionEscritura, double mbsPorConsumidor,
                                int retencionDias, int factorReplicacion, int brokers, double margen) {
        if (entradaMbs <= 0 || mbsPorParticionEscritura <= 0 || mbsPorConsumidor <= 0 || retencionDias < 1
                || factorReplicacion < 1 || brokers < factorReplicacion || margen < 1) {
            throw new IllegalArgumentException("parámetros inválidos");
        }
        int porEscritura = (int) Math.ceil(entradaMbs / mbsPorParticionEscritura);
        int porLectura = (int) Math.ceil(entradaMbs / mbsPorConsumidor);
        int particiones = Math.max(1, (int) Math.ceil(Math.max(porEscritura, porLectura) * margen));
        double totalGiB = entradaMbs * 86_400 * retencionDias * factorReplicacion * margen / 1024.0;
        List<String> avisos = new ArrayList<>();
        if (factorReplicacion < 3) {
            avisos.add("RF < 3: no toleras la caída de un broker sin perder disponibilidad o durabilidad");
        }
        if (brokers % 3 != 0) {
            avisos.add("el número de brokers debe ser múltiplo de las zonas de disponibilidad (3)");
        }
        if ((double) particiones * factorReplicacion / brokers > 1000) {
            avisos.add("muchas réplicas de partición por broker: más sobrecarga (verifica los límites del tipo de broker)");
        }
        if (particiones > 100) {
            avisos.add("muchas particiones en un tópico: más memoria, más tiempo de rebalanceo");
        }
        return new Plan(particiones, totalGiB, totalGiB / brokers, Math.max(1, factorReplicacion - 1), avisos);
    }
}
```

### 2.3 Propiedades de cliente con IAM
Un solo lugar que construye las propiedades de productor, consumidor y administrador, con los valores recomendados (`acks=all`, idempotencia, confirmación manual) y la autenticación `AWS_MSK_IAM`. Sirve igual a Spring, reactor-kafka y Quarkus.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.HashMap;
import java.util.Map;
import java.util.regex.Pattern;
import org.apache.kafka.clients.CommonClientConfigs;
import org.apache.kafka.clients.consumer.ConsumerConfig;
import org.apache.kafka.clients.producer.ProducerConfig;
import org.apache.kafka.common.config.SaslConfigs;
import org.apache.kafka.common.serialization.StringDeserializer;
import org.apache.kafka.common.serialization.StringSerializer;

public final class PropiedadesMsk {
    private static final Pattern ROL = Pattern.compile("arn:aws[a-z-]*:iam::[0-9]{12}:role/[\\w+=,.@/-]+");

    private PropiedadesMsk() {}

    /** @param rolArn null = usa la cadena de credenciales del entorno; con valor, asume ese rol. */
    public static Map<String, Object> iam(String bootstrap, String rolArn) {
        if (rolArn != null && !ROL.matcher(rolArn).matches()) {
            throw new IllegalArgumentException("ARN de rol inválido");
        }
        Map<String, Object> p = new HashMap<>();
        p.put(CommonClientConfigs.BOOTSTRAP_SERVERS_CONFIG, bootstrap);
        p.put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, "SASL_SSL");
        p.put(SaslConfigs.SASL_MECHANISM, "AWS_MSK_IAM");
        p.put(SaslConfigs.SASL_JAAS_CONFIG, "software.amazon.msk.auth.iam.IAMLoginModule required"
                + (rolArn == null ? "" : " awsRoleArn=\"" + rolArn + "\"") + ";");
        p.put(SaslConfigs.SASL_CLIENT_CALLBACK_HANDLER_CLASS, "software.amazon.msk.auth.iam.IAMClientCallbackHandler");
        return p;
    }

    public static Map<String, Object> scram(String bootstrap, String usuario, String clave) {
        Map<String, Object> p = new HashMap<>();
        p.put(CommonClientConfigs.BOOTSTRAP_SERVERS_CONFIG, bootstrap);
        p.put(CommonClientConfigs.SECURITY_PROTOCOL_CONFIG, "SASL_SSL");
        p.put(SaslConfigs.SASL_MECHANISM, "SCRAM-SHA-512");
        p.put(SaslConfigs.SASL_JAAS_CONFIG, "org.apache.kafka.common.security.scram.ScramLoginModule required username=\""
                + escapar(usuario) + "\" password=\"" + escapar(clave) + "\";");
        return p;
    }

    private static String escapar(String s) {
        return s.replace("\\", "\\\\").replace("\"", "\\\"");
    }

    public static Map<String, Object> admin(String bootstrap) {
        return iam(bootstrap, null);
    }

    public static Map<String, Object> productor(String bootstrap, String clientId) {
        Map<String, Object> p = iam(bootstrap, null);
        p.put(ProducerConfig.CLIENT_ID_CONFIG, clientId);
        p.put(ProducerConfig.ACKS_CONFIG, "all");
        p.put(ProducerConfig.ENABLE_IDEMPOTENCE_CONFIG, true);
        p.put(ProducerConfig.COMPRESSION_TYPE_CONFIG, "lz4");
        p.put(ProducerConfig.LINGER_MS_CONFIG, 20);
        p.put(ProducerConfig.BATCH_SIZE_CONFIG, 65_536);
        p.put(ProducerConfig.DELIVERY_TIMEOUT_MS_CONFIG, 120_000);
        p.put(ProducerConfig.MAX_IN_FLIGHT_REQUESTS_PER_CONNECTION, 5);
        p.put(ProducerConfig.KEY_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        p.put(ProducerConfig.VALUE_SERIALIZER_CLASS_CONFIG, StringSerializer.class);
        return p;
    }

    /** @param instanciaEstatica identificador estable por réplica (membresía estática: menos rebalanceos); null = dinámica. */
    public static Map<String, Object> consumidor(String bootstrap, String grupo, String clientId, String instanciaEstatica) {
        Map<String, Object> p = iam(bootstrap, null);
        p.put(ConsumerConfig.GROUP_ID_CONFIG, grupo);
        p.put(ConsumerConfig.CLIENT_ID_CONFIG, clientId);
        p.put(ConsumerConfig.ENABLE_AUTO_COMMIT_CONFIG, false);
        p.put(ConsumerConfig.AUTO_OFFSET_RESET_CONFIG, "earliest");
        p.put(ConsumerConfig.MAX_POLL_RECORDS_CONFIG, 100);
        p.put(ConsumerConfig.MAX_POLL_INTERVAL_MS_CONFIG, 300_000);
        p.put(ConsumerConfig.SESSION_TIMEOUT_MS_CONFIG, 45_000);
        p.put(ConsumerConfig.HEARTBEAT_INTERVAL_MS_CONFIG, 15_000);
        p.put(ConsumerConfig.KEY_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class);
        p.put(ConsumerConfig.VALUE_DESERIALIZER_CLASS_CONFIG, StringDeserializer.class);
        if (instanciaEstatica != null) {
            p.put(ConsumerConfig.GROUP_INSTANCE_ID_CONFIG, instanciaEstatica);
        }
        return p;
    }
}
```

### 2.4 Crear tópicos de forma idempotente (y detectar desvíos)
Los tópicos se administran con la API de Kafka, desde un lugar con red hacia los brokers (idealmente un paso del *pipeline* o un `Job`). Si el tópico ya existe, **no falla**: compara particiones, réplicas y `min.insync.replicas` y te dice si hay diferencias.
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutionException;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.TimeoutException;
import org.apache.kafka.clients.admin.Admin;
import org.apache.kafka.clients.admin.Config;
import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.clients.admin.TopicDescription;
import org.apache.kafka.common.config.ConfigResource;
import org.apache.kafka.common.errors.TopicExistsException;

public final class AdminTopicos {
    public record Definicion(String nombre, int particiones, short factorReplicacion, Map<String, String> config) {
        /** RF=3, min.insync.replicas=2 y retención en horas. */
        public static Definicion estandar(String nombre, int particiones, int retencionHoras) {
            return new Definicion(nombre, particiones, (short) 3, Map.of("min.insync.replicas", "2",
                    "retention.ms", String.valueOf(retencionHoras * 3_600_000L), "cleanup.policy", "delete"));
        }

        NewTopic comoNuevo() {
            return new NewTopic(nombre, particiones, factorReplicacion).configs(config);
        }
    }

    private AdminTopicos() {}

    public static Map<String, String> asegurar(Map<String, Object> props, List<Definicion> definiciones) {
        try (Admin admin = Admin.create(props)) {
            return asegurar(admin, definiciones);
        }
    }

    /** @return nombre → "creado" | "existe" | "existe con diferencias: …" */
    public static Map<String, String> asegurar(Admin admin, List<Definicion> definiciones) {
        for (Definicion d : definiciones) {
            var problemas = NombresTopico.problemas(d.nombre());
            if (!problemas.isEmpty()) {
                throw new IllegalArgumentException(d.nombre() + ": " + problemas);
            }
        }
        var resultado = admin.createTopics(definiciones.stream().map(Definicion::comoNuevo).toList());
        Map<String, String> estado = new LinkedHashMap<>();
        List<Definicion> existentes = new ArrayList<>();
        for (Definicion d : definiciones) {
            try {
                resultado.values().get(d.nombre()).get(30, TimeUnit.SECONDS);
                estado.put(d.nombre(), "creado");
            } catch (ExecutionException e) {
                if (e.getCause() instanceof TopicExistsException) {
                    existentes.add(d);
                } else {
                    throw new IllegalStateException(d.nombre() + ": " + e.getCause().getMessage(), e.getCause());
                }
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw new IllegalStateException(e);
            } catch (TimeoutException e) {
                throw new IllegalStateException("tiempo agotado creando " + d.nombre(), e);
            }
        }
        if (!existentes.isEmpty()) {
            estado.putAll(comparar(admin, existentes));
        }
        return estado;
    }

    private static Map<String, String> comparar(Admin admin, List<Definicion> existentes) {
        try {
            List<String> nombres = existentes.stream().map(Definicion::nombre).toList();
            Map<String, TopicDescription> descripciones = admin.describeTopics(nombres).allTopicNames().get(30, TimeUnit.SECONDS);
            List<ConfigResource> recursos = nombres.stream().map(n -> new ConfigResource(ConfigResource.Type.TOPIC, n)).toList();
            Map<ConfigResource, Config> configs = admin.describeConfigs(recursos).all().get(30, TimeUnit.SECONDS);
            Map<String, String> estado = new LinkedHashMap<>();
            for (Definicion d : existentes) {
                TopicDescription desc = descripciones.get(d.nombre());
                List<String> diffs = new ArrayList<>();
                int particiones = desc.partitions().size();
                if (particiones != d.particiones()) {
                    diffs.add("particiones " + particiones + " ≠ " + d.particiones() + " (solo se pueden aumentar)");
                }
                int replicas = desc.partitions().get(0).replicas().size();
                if (replicas != d.factorReplicacion()) {
                    diffs.add("réplicas " + replicas + " ≠ " + d.factorReplicacion());
                }
                var cfg = configs.get(new ConfigResource(ConfigResource.Type.TOPIC, d.nombre()));
                String esperado = d.config().get("min.insync.replicas");
                String actual = cfg.get("min.insync.replicas") == null ? null : cfg.get("min.insync.replicas").value();
                if (esperado != null && !esperado.equals(actual)) {
                    diffs.add("min.insync.replicas " + actual + " ≠ " + esperado);
                }
                estado.put(d.nombre(), diffs.isEmpty() ? "existe" : "existe con diferencias: " + String.join("; ", diffs));
            }
            return estado;
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw new IllegalStateException(e);
        } catch (ExecutionException | TimeoutException e) {
            throw new IllegalStateException("no se pudo comparar la configuración de los tópicos", e);
        }
    }
}
```

## 3. Spring MVC (imperativo, Spring for Apache Kafka)
```java
import java.util.Map;
import java.util.concurrent.CompletableFuture;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.apache.kafka.clients.admin.NewTopic;
import org.apache.kafka.common.TopicPartition;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.kafka.config.TopicBuilder;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.kafka.listener.DeadLetterPublishingRecoverer;
import org.springframework.kafka.listener.DefaultErrorHandler;
import org.springframework.kafka.support.Acknowledgment;
import org.springframework.stereotype.Component;
import org.springframework.kafka.support.ExponentialBackOffWithMaxRetries;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import tools.jackson.databind.json.JsonMapper;

@Configuration
class KafkaMskConfig {
    /** KafkaAdmin crea el tópico al arrancar si no existe (con RF=3 y min.insync.replicas=2). Preferible: hacerlo en el pipeline. */
    @Bean
    NewTopic pedidosCreados() {
        return TopicBuilder.name("pedidos.orden.creada.v1").partitions(6).replicas(3).config("min.insync.replicas", "2").build();
    }

    /** Reintentos con espera creciente y, al agotarlos, el mensaje va a «.dlq» (no se pierde ni bloquea la partición). */
    @Bean
    DefaultErrorHandler errorHandler(KafkaTemplate<Object, Object> plantilla) {
        var recuperador = new DeadLetterPublishingRecoverer(plantilla, (r, e) -> new TopicPartition(r.topic() + ".dlq", -1));
        var espera = new ExponentialBackOffWithMaxRetries(4);
        espera.setInitialInterval(500);
        espera.setMultiplier(2.0);
        espera.setMaxInterval(10_000);
        return new DefaultErrorHandler(recuperador, espera);
    }
}

record OrdenKafkaDto(String idOrden, String total, String envio) {}

@RestController
class PedidosKafkaController {
    private final KafkaTemplate<String, String> kafka;
    private final JsonMapper json;

    PedidosKafkaController(KafkaTemplate<String, String> kafka, JsonMapper json) {
        this.kafka = kafka;
        this.json = json;
    }

    /** La clave (idOrden) garantiza el orden de los eventos de una misma orden. */
    @PostMapping("/pedidos-kafka")
    CompletableFuture<Map<String, Object>> publicar(@RequestBody OrdenKafkaDto o) {
        return kafka.send("pedidos.orden.creada.v1", o.idOrden(), json.writeValueAsString(o))
                .thenApply(r -> Map.of("particion", r.getRecordMetadata().partition(), "offset", r.getRecordMetadata().offset()));
    }
}

@Component
class FacturacionKafkaListener {
    /** Commit manual: solo se confirma si el negocio terminó. Si lanza, el manejador de errores reintenta y desvía a la DLQ. */
    @KafkaListener(topics = "pedidos.orden.creada.v1", groupId = "facturacion", concurrency = "3")
    void recibir(ConsumerRecord<String, String> registro, Acknowledgment ack) {
        System.out.println(registro.partition() + "/" + registro.offset() + " " + registro.key());   // tu negocio (idempotente por clave)
        ack.acknowledge();
    }
}
```

## 4. Spring WebFlux (reactivo, reactor-kafka)
```java
import jakarta.annotation.PostConstruct;
import jakarta.annotation.PreDestroy;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import org.apache.kafka.clients.producer.ProducerRecord;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.Disposable;
import reactor.core.publisher.Mono;
import reactor.kafka.receiver.KafkaReceiver;
import reactor.kafka.receiver.ReceiverOptions;
import reactor.kafka.sender.KafkaSender;
import reactor.kafka.sender.SenderOptions;
import reactor.kafka.sender.SenderRecord;
import reactor.util.retry.Retry;

@Configuration
class KafkaReactivoConfig {
    @Bean(destroyMethod = "close")
    KafkaSender<String, String> sender(@Value("${app.msk-bootstrap}") String bootstrap) {
        return KafkaSender.create(SenderOptions.<String, String>create(PropiedadesMsk.productor(bootstrap, "pedidos-api")));
    }
}

record OrdenKafkaReactivaDto(String idOrden, String json) {}

@RestController
class PedidosKafkaReactivoController {
    private final KafkaSender<String, String> sender;

    PedidosKafkaReactivoController(KafkaSender<String, String> sender) {
        this.sender = sender;
    }

    @PostMapping("/pedidos-kafka-r")
    Mono<Map<String, Object>> publicar(@RequestBody Mono<OrdenKafkaReactivaDto> cuerpo) {
        return cuerpo.flatMap(o -> sender
                .send(Mono.just(SenderRecord.create(new ProducerRecord<>("pedidos.orden.creada.v1", o.idOrden(), o.json()), o.idOrden())))
                .next()
                .flatMap(r -> r.exception() != null
                        ? Mono.<Map<String, Object>>error(r.exception())
                        : Mono.just(Map.<String, Object>of("particion", r.recordMetadata().partition(), "offset", r.recordMetadata().offset()))));
    }
}

@Component
class FacturacionReactiva {
    private final String bootstrap;
    private Disposable suscripcion;

    FacturacionReactiva(@Value("${app.msk-bootstrap}") String bootstrap) {
        this.bootstrap = bootstrap;
    }

    @PostConstruct
    void iniciar() {
        var opciones = ReceiverOptions.<String, String>create(PropiedadesMsk.consumidor(bootstrap, "facturacion", "fact-r", null))
                .subscription(List.of("pedidos.orden.creada.v1"));
        suscripcion = KafkaReceiver.create(opciones).receive()
                // concatMap: un mensaje a la vez por partición lógica del flujo; commit solo tras procesar
                .concatMap(r -> procesar(r.key(), r.value()).then(r.receiverOffset().commit()))
                .retryWhen(Retry.backoff(Long.MAX_VALUE, Duration.ofSeconds(1)).maxBackoff(Duration.ofSeconds(30)))
                .subscribe();
    }

    private Mono<Void> procesar(String clave, String valor) {
        return Mono.fromRunnable(() -> System.out.println("orden " + clave));   // tu negocio (idempotente)
    }

    @PreDestroy
    void detener() {
        if (suscripcion != null) {
            suscripcion.dispose();
        }
    }
}
```

## 5. Quarkus (imperativo)
```java
import io.quarkus.runtime.StartupEvent;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.event.Observes;
import java.util.List;
import org.eclipse.microprofile.config.inject.ConfigProperty;

/** Asegura los tópicos al arrancar. En producción suele ir en el pipeline; aquí se muestra el AdminClient idempotente. */
@ApplicationScoped
class TopicosAlArrancar {
    @ConfigProperty(name = "kafka.bootstrap.servers")
    String bootstrap;

    void alArrancar(@Observes StartupEvent ev) {
        var estado = AdminTopicos.asegurar(PropiedadesMsk.admin(bootstrap),
                List.of(AdminTopicos.Definicion.estandar("pedidos.orden.creada.v1", 6, 72)));
        estado.forEach((t, e) -> System.out.println(t + ": " + e));
    }
}
```
```java
import io.smallrye.common.annotation.Blocking;
import io.smallrye.reactive.messaging.kafka.Record;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.util.Map;
import java.util.concurrent.TimeUnit;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.eclipse.microprofile.reactive.messaging.Channel;
import org.eclipse.microprofile.reactive.messaging.Emitter;
import org.eclipse.microprofile.reactive.messaging.Incoming;

@Path("/pedidos-kafka")
class PedidosKafkaRecurso {
    @Inject
    @Channel("pedidos-out")
    Emitter<Record<String, String>> emisor;

    /** Espera la confirmación del broker (acks=all) antes de responder. */
    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public Map<String, String> publicar(Map<String, String> orden) throws Exception {
        emisor.send(Record.of(orden.get("idOrden"), orden.toString())).toCompletableFuture().get(10, TimeUnit.SECONDS);
        return Map.of("estado", "publicado");
    }
}

@ApplicationScoped
class FacturacionKafka {
    /** Hilo de trabajo (@Blocking): se confirma al terminar sin error; si lanza, se aplica la estrategia (cola de fallos). */
    @Incoming("pedidos-in")
    @Blocking
    public void recibir(ConsumerRecord<String, String> registro) {
        System.out.println(registro.partition() + "/" + registro.offset() + " " + registro.key());   // tu negocio (idempotente)
    }
}
```

## 6. Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import io.smallrye.reactive.messaging.MutinyEmitter;
import io.smallrye.reactive.messaging.kafka.Record;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.Consumes;
import jakarta.ws.rs.POST;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.Produces;
import jakarta.ws.rs.core.MediaType;
import java.util.Map;
import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.eclipse.microprofile.reactive.messaging.Channel;
import org.eclipse.microprofile.reactive.messaging.Incoming;

@Path("/pedidos-kafka-r")
class PedidosKafkaMutinyRecurso {
    @Inject
    @Channel("pedidos-out")
    MutinyEmitter<Record<String, String>> emisor;

    @POST
    @Consumes(MediaType.APPLICATION_JSON)
    @Produces(MediaType.APPLICATION_JSON)
    public Uni<Map<String, String>> publicar(Map<String, String> orden) {
        return emisor.send(Record.of(orden.get("idOrden"), orden.toString())).replaceWith(Map.of("estado", "publicado"));
    }
}

@ApplicationScoped
class FacturacionKafkaReactiva {
    /** Devuelve un Uni: el mensaje se confirma cuando el Uni termina bien; si falla, se aplica la estrategia (cola de fallos). */
    @Incoming("pedidos-in")
    public Uni<Void> recibir(ConsumerRecord<String, String> registro) {
        return Uni.createFrom().item(registro).invoke(r -> System.out.println("orden " + r.key())).replaceWithVoid();   // tu negocio (idempotente)
    }
}
```

## 7. Permisos
Productor y consumidor: [`ejemplos/json/politica-productor.json`](ejemplos/json/politica-productor.json) y [`ejemplos/json/politica-consumidor.json`](ejemplos/json/politica-consumidor.json) (clúster + tópico + **grupo**).

## 8. Qué NO hacer desde Java
- **No** pongas credenciales en las propiedades: usa `AWS_MSK_IAM` con el rol del servicio.
- **No** uses el autocommit: confirma después de procesar.
- **No** procesar un lote más lento que `max.poll.interval.ms`: reduce `max.poll.records` o aísla la parte lenta.
- **No** crees tópicos «al vuelo» desde el productor: valida el nombre y créalos por código con RF=3 y `min.insync.replicas=2`.
- **No** bloquees el hilo de eventos en Quarkus o WebFlux (`@Blocking`, `boundedElastic`).
- **No** cambies el número de particiones de un tópico con clave sin pensar en el orden: las claves se reparten distinto.
- **No** asumas entrega única: consumidor idempotente.
