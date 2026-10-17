# AWS · Secrets Manager · Uso desde Java

Regla de oro: **el secreto se lee al arrancar y cuando cambia, no en cada petición**. Con rotación hay que resolver dos cosas: una **caché con TTL** y **qué hacer cuando la credencial vieja deja de funcionar**. Versiones: Java 21, Spring Boot 4.1, Quarkus 3.40, AWS SDK v2 (BOM 2.56), Spring Cloud AWS 4.2 *(verifica la matriz de compatibilidad con tu versión de Spring Boot)*.

## 1. Lo más simple en Spring: Spring Cloud AWS
```properties
# application.properties — el secreto se carga como propiedades al arrancar
spring.config.import=aws-secretsmanager:prod/pedidos/db
# Si el secreto es un JSON {"username":"…","password":"…"}, cada clave queda como propiedad:
spring.datasource.username=${username}
spring.datasource.password=${password}
```
Ventaja: cero código. Límites: **se lee una vez al arrancar**; tras una rotación hay que reiniciar o refrescar (ver §3); y las versiones de Spring Cloud AWS cambian su API entre versiones mayores (por ejemplo, la clase `SecretsManagerTemplate` de la 3.x no está en la 4.2): verifica la guía de tu versión.
```java
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

@Component
class CredencialesCargadasAlArrancar {
    private final String usuario;

    CredencialesCargadasAlArrancar(@Value("${username}") String usuario) {
        this.usuario = usuario;       // viene del JSON del secreto; la clave NO se guarda en campos ni se imprime
    }

    String usuario() { return usuario; }
}
```

## 2. Con el SDK: caché con TTL y reintento ante rotación

### Núcleo común
```java
// (clase reutilizada en los bloques siguientes, ambos)
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.function.Function;
import java.util.function.Predicate;
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;
import software.amazon.awssdk.services.secretsmanager.model.GetSecretValueRequest;

record Secreto(String valor, String versionId, Instant cargadoEn) {}

/** Parser mínimo para secretos planos {"clave":"valor", "port":5432}. Sin dependencias (en tu servicio puedes usar Jackson). */
final class MiniJson {
    private MiniJson() {}

    static Map<String, String> planoAMapa(String s) {
        int[] i = {0};
        Map<String, String> r = new LinkedHashMap<>();
        blancos(s, i);
        esperar(s, i, '{');
        blancos(s, i);
        if (mirar(s, i) == '}') return r;
        while (true) {
            blancos(s, i);
            String k = cadena(s, i);
            blancos(s, i);
            esperar(s, i, ':');
            blancos(s, i);
            String v;
            if (mirar(s, i) == '"') {
                v = cadena(s, i);
            } else {
                int ini = i[0];
                while (i[0] < s.length() && ",}".indexOf(s.charAt(i[0])) < 0) i[0]++;
                v = s.substring(ini, i[0]).trim();
                if (v.startsWith("{") || v.startsWith("[")) throw new IllegalArgumentException("Solo se admiten objetos planos");
                if (v.equals("null")) v = null;
            }
            r.put(k, v);
            blancos(s, i);
            char c = mirar(s, i);
            i[0]++;
            if (c == '}') return r;
            if (c != ',') throw new IllegalArgumentException("JSON inválido en la posición " + i[0]);
        }
    }

    private static char mirar(String s, int[] i) {
        if (i[0] >= s.length()) throw new IllegalArgumentException("JSON incompleto");
        return s.charAt(i[0]);
    }

    private static void esperar(String s, int[] i, char c) {
        if (mirar(s, i) != c) throw new IllegalArgumentException("Se esperaba '" + c + "' en " + i[0]);
        i[0]++;
    }

    private static void blancos(String s, int[] i) {
        while (i[0] < s.length() && Character.isWhitespace(s.charAt(i[0]))) i[0]++;
    }

    private static String cadena(String s, int[] i) {
        esperar(s, i, '"');
        StringBuilder b = new StringBuilder();
        while (true) {
            char c = mirar(s, i);
            i[0]++;
            if (c == '"') return b.toString();
            if (c != '\\') { b.append(c); continue; }
            char e = mirar(s, i);
            i[0]++;
            switch (e) {
                case 'n' -> b.append('\n');
                case 't' -> b.append('\t');
                case 'r' -> b.append('\r');
                case 'b' -> b.append('\b');
                case 'f' -> b.append('\f');
                case 'u' -> {
                    b.append((char) Integer.parseInt(s.substring(i[0], i[0] + 4), 16));
                    i[0] += 4;
                }
                default -> b.append(e);       // \" \\ \/
            }
        }
    }
}

/** Caché con TTL: una sola carga por secreto a la vez; si AWS falla, sirve lo último conocido y reintenta pronto. */
final class CacheSecretos {
    private record Entrada(Secreto secreto, Instant vence) {}

    private final Map<String, Entrada> mapa = new ConcurrentHashMap<>();
    private final Function<String, Secreto> cargador;
    private final Duration ttl;
    private final Clock reloj;

    CacheSecretos(Function<String, Secreto> cargador, Duration ttl, Clock reloj) {
        this.cargador = cargador;
        this.ttl = ttl;
        this.reloj = reloj;
    }

    Secreto obtener(String id) {
        Entrada e = mapa.get(id);
        if (e != null && reloj.instant().isBefore(e.vence())) return e.secreto();
        return mapa.compute(id, (k, actual) -> {
            Instant ahora = reloj.instant();
            if (actual != null && ahora.isBefore(actual.vence())) return actual;      // otro hilo ya refrescó
            try {
                return new Entrada(cargador.apply(k), ahora.plus(ttl));
            } catch (RuntimeException ex) {
                if (actual != null) return new Entrada(actual.secreto(), ahora.plusSeconds(30));   // degradación elegante
                throw ex;
            }
        }).secreto();
    }

    void invalidar(String id) { mapa.remove(id); }
}

final class SecretosAws {
    private final SecretsManagerClient sm;
    private final CacheSecretos cache;

    SecretosAws(SecretsManagerClient sm, Duration ttl) {
        this.sm = sm;
        this.cache = new CacheSecretos(this::cargar, ttl, Clock.systemUTC());
    }

    private Secreto cargar(String id) {
        var r = sm.getSecretValue(GetSecretValueRequest.builder().secretId(id).build());   // AWSCURRENT por defecto
        return new Secreto(r.secretString(), r.versionId(), Instant.now());
    }

    Map<String, String> json(String id) { return MiniJson.planoAMapa(cache.obtener(id).valor()); }

    Secreto secreto(String id) { return cache.obtener(id); }

    void recargar(String id) { cache.invalidar(id); }

    /** Ejecuta con la credencial vigente; si falla la autenticación (rotación), recarga y reintenta UNA vez. */
    <T> T conReintentoPorRotacion(String id, Predicate<RuntimeException> esFalloDeAutenticacion, Function<Map<String, String>, T> operacion) {
        try {
            return operacion.apply(json(id));
        } catch (RuntimeException e) {
            if (!esFalloDeAutenticacion.test(e)) throw e;
            recargar(id);
            return operacion.apply(json(id));
        }
    }
}

record EstadoSecreto(String id, String versionId, long edadSegundos, java.util.List<String> claves) {}
```
Notas: `GetSecretValue` sin `versionStage` devuelve `AWSCURRENT`; la lista de claves se devuelve **sin valores** (nunca expongas el contenido).

### Spring MVC (imperativo): cliente, estado y actualización del pool Hikari
```java
import com.zaxxer.hikari.HikariDataSource;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.annotation.EnableScheduling;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Component;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;

@Configuration
@EnableScheduling
class SecretosConfig {
    @Bean(destroyMethod = "close")
    SecretsManagerClient secretsManager() {
        return SecretsManagerClient.builder().region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1"))).build();
    }

    @Bean
    SecretosAws secretos(SecretsManagerClient sm, @Value("${secretos.ttl:PT5M}") Duration ttl) {
        return new SecretosAws(sm, ttl);
    }
}

/** Si el secreto de la base cambió (rotación), las conexiones NUEVAS usan la clave nueva y las viejas se retiran. */
@Component
class RefrescoCredencialesDb {
    private final SecretosAws secretos;
    private final HikariDataSource pool;
    private final String idSecreto;
    private volatile String versionAplicada = "";

    RefrescoCredencialesDb(SecretosAws secretos, HikariDataSource pool, @Value("${secretos.db:prod/pedidos/db}") String idSecreto) {
        this.secretos = secretos;
        this.pool = pool;
        this.idSecreto = idSecreto;
    }

    @Scheduled(fixedDelayString = "PT1M", initialDelayString = "PT1M")
    void revisar() {
        try {
            Secreto s = secretos.secreto(idSecreto);
            if (s.versionId().equals(versionAplicada)) return;
            Map<String, String> c = secretos.json(idSecreto);
            pool.getHikariConfigMXBean().setUsername(c.get("username"));
            pool.getHikariConfigMXBean().setPassword(c.get("password"));
            pool.getHikariPoolMXBean().softEvictConnections();      // retira las conexiones con la credencial anterior
            versionAplicada = s.versionId();
        } catch (RuntimeException e) {
            // no tumbar la app por un fallo temporal: se reintenta en el siguiente ciclo
        }
    }
}

@RestController
class SecretosController {
    private final SecretosAws secretos;

    SecretosController(SecretosAws secretos) { this.secretos = secretos; }

    @GetMapping("/secretos/estado")
    EstadoSecreto estado(@RequestParam String id) {
        Secreto s = secretos.secreto(id);
        List<String> claves = List.copyOf(secretos.json(id).keySet());
        return new EstadoSecreto(id, s.versionId(), Duration.between(s.cargadoEn(), Instant.now()).toSeconds(), claves);
    }
}
```

### Spring WebFlux (reactivo)
```java
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import reactor.core.publisher.Mono;
import reactor.core.scheduler.Schedulers;

@RestController
class SecretosReactivoController {
    private final SecretosAws secretos;

    SecretosReactivoController(SecretosAws secretos) { this.secretos = secretos; }

    @GetMapping("/reactivo/secretos/estado")
    Mono<EstadoSecreto> estado(@RequestParam String id) {
        return Mono.fromCallable(() -> {
                    Secreto s = secretos.secreto(id);                      // puede llamar a AWS (bloquea) la primera vez
                    List<String> claves = List.copyOf(secretos.json(id).keySet());
                    return new EstadoSecreto(id, s.versionId(), Duration.between(s.cargadoEn(), Instant.now()).toSeconds(), claves);
                })
                .subscribeOn(Schedulers.boundedElastic());
    }
}
```
En un servicio reactivo de verdad, precarga el secreto al arrancar y refréscalo con un `Flux.interval(...)` en `boundedElastic`; así el camino de las peticiones **nunca** toca la red.

### Quarkus (imperativo): proveedor de credenciales para Agroal
```java
import io.quarkus.credentials.CredentialsProvider;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.enterprise.inject.Produces;
import jakarta.inject.Inject;
import jakarta.inject.Named;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.time.Duration;
import java.time.Instant;
import java.util.List;
import java.util.Map;
import org.eclipse.microprofile.config.inject.ConfigProperty;
import software.amazon.awssdk.regions.Region;
import software.amazon.awssdk.services.secretsmanager.SecretsManagerClient;

@ApplicationScoped
class SecretosProductores {
    @Produces
    @ApplicationScoped
    SecretsManagerClient secretsManager() {
        return SecretsManagerClient.builder().region(Region.of(System.getenv().getOrDefault("AWS_REGION", "us-east-1"))).build();
    }

    @Produces
    @ApplicationScoped
    SecretosAws secretos(SecretsManagerClient sm) {
        return new SecretosAws(sm, Duration.ofMinutes(5));
    }
}

/** Agroal pide usuario y clave a este proveedor cada vez que abre una conexión NUEVA: la rotación se absorbe sola. */
@ApplicationScoped
@Named("secretos-db")
class CredencialesDb implements CredentialsProvider {
    @Inject
    SecretosAws secretos;
    @ConfigProperty(name = "secretos.db", defaultValue = "prod/pedidos/db")
    String idSecreto;

    @Override
    public Map<String, String> getCredentials(String credentialsProviderName) {
        Map<String, String> c = secretos.json(idSecreto);
        return Map.of(USER_PROPERTY_NAME, c.get("username"), PASSWORD_PROPERTY_NAME, c.get("password"));
    }
}

@Path("/secretos/estado")
public class SecretosResource {
    @Inject
    SecretosAws secretos;

    @GET
    public EstadoSecreto estado(@QueryParam("id") String id) {
        Secreto s = secretos.secreto(id);
        List<String> claves = List.copyOf(secretos.json(id).keySet());
        return new EstadoSecreto(id, s.versionId(), Duration.between(s.cargadoEn(), Instant.now()).toSeconds(), claves);
    }
}
```
```properties
# application.properties (Quarkus)
quarkus.datasource.db-kind=postgresql
quarkus.datasource.jdbc.url=jdbc:postgresql://pedidos.cluster-xxxx.us-east-1.rds.amazonaws.com:5432/pedidos
quarkus.datasource.credentials-provider=secretos-db
secretos.db=prod/pedidos/db
```

### Quarkus reactivo (Mutiny)
```java
import io.smallrye.mutiny.Uni;
import io.smallrye.mutiny.infrastructure.Infrastructure;
import jakarta.inject.Inject;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;
import jakarta.ws.rs.QueryParam;
import java.time.Duration;
import java.time.Instant;
import java.util.List;

@Path("/reactivo/secretos/estado")
public class SecretosReactivoResource {
    @Inject
    SecretosAws secretos;

    @GET
    public Uni<EstadoSecreto> estado(@QueryParam("id") String id) {
        return Uni.createFrom().item(() -> {
                    Secreto s = secretos.secreto(id);
                    List<String> claves = List.copyOf(secretos.json(id).keySet());
                    return new EstadoSecreto(id, s.versionId(), Duration.between(s.cargadoEn(), Instant.now()).toSeconds(), claves);
                })
                .runSubscriptionOn(Infrastructure.getDefaultWorkerPool());
    }
}
```

## 3. Estrategias frente a la rotación (resumen)
| Estrategia | Cómo | Cuándo |
|---|---|---|
| **Credencial por conexión nueva** | Quarkus: `CredentialsProvider`; Spring: refresco del pool (arriba) | Bases de datos con pool |
| **Reintento ante fallo de autenticación** | `conReintentoPorRotacion` | Claves de API de terceros |
| **Reinicio controlado** | Evento de EventBridge (`RotationSucceeded`) → redespliegue | Config cargada solo al arrancar |
| **Controlador de la rotación** | Usuarios alternos (sin cortes) | Siempre que se pueda |

## 4. Qué NO hacer desde Java
- No imprimir el valor (ni la clave del pool) en logs ni en excepciones; `toString()` de registros con claves es un riesgo: nunca los expongas.
- No devolver el secreto por una API (el endpoint de estado solo lista **claves**).
- No leer el secreto por cada petición.
- No guardar el secreto en variables estáticas sin expiración.
