# Azure · Entra ID · Uso desde Java

Dos papeles distintos:
- **Proteger tu API** (resource server): validar el token que llega.
- **Llamar a otra API** (client): obtener un token y adjuntarlo.

## 1. Proteger tu API: Spring Boot imperativo (Spring MVC)

Dependencia:
```xml
<dependency>
  <groupId>org.springframework.boot</groupId>
  <artifactId>spring-boot-starter-oauth2-resource-server</artifactId>
</dependency>
```
```properties
# application.properties
spring.security.oauth2.resourceserver.jwt.issuer-uri=https://login.microsoftonline.com/<TENANT_ID>/v2.0
app.seguridad.audiencia=api://<CLIENT_ID_DE_LA_API>
```
```java
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.annotation.web.configuration.EnableWebSecurity;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.jwt.*;
import org.springframework.security.web.SecurityFilterChain;

@Configuration
@EnableWebSecurity
class SeguridadConfig {

    @Bean
    SecurityFilterChain filtro(HttpSecurity http) throws Exception {
        http.authorizeHttpRequests(a -> a
                .requestMatchers("/actuator/health/**").permitAll()
                .requestMatchers("/api/pedidos/**").hasAuthority("SCOPE_pedidos.read")   // token con usuario (scp)
                .requestMatchers("/interno/**").hasAuthority("APPROLE_Catalogo.Read")      // token de aplicación (roles)
                .anyRequest().authenticated())
            .oauth2ResourceServer(o -> o.jwt(Customizer.withDefaults()));
        return http.build();
    }

    // Valida emisor Y audiencia (lo que casi todos olvidan)
    @Bean
    JwtDecoder jwtDecoder(@Value("${spring.security.oauth2.resourceserver.jwt.issuer-uri}") String issuer,
                          @Value("${app.seguridad.audiencia}") String audiencia) {
        NimbusJwtDecoder decoder = JwtDecoders.fromIssuerLocation(issuer);
        OAuth2TokenValidator<Jwt> conIssuer = JwtValidators.createDefaultWithIssuer(issuer);
        OAuth2TokenValidator<Jwt> conAudiencia = jwt -> jwt.getAudience().contains(audiencia)
                ? org.springframework.security.oauth2.core.OAuth2TokenValidatorResult.success()
                : org.springframework.security.oauth2.core.OAuth2TokenValidatorResult.failure(
                        new org.springframework.security.oauth2.core.OAuth2Error("invalid_token", "Audiencia incorrecta", null));
        decoder.setJwtValidator(new DelegatingOAuth2TokenValidator<>(conIssuer, conAudiencia));
        return decoder;
    }
}
```
Para mapear la claim `roles` a autoridades `APPROLE_*`:
```java
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.core.GrantedAuthority;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.oauth2.server.resource.authentication.JwtAuthenticationConverter;
import org.springframework.security.oauth2.server.resource.authentication.JwtGrantedAuthoritiesConverter;

@Configuration
class ConversorJwtConfig {

    @Bean
    JwtAuthenticationConverter convertidor() {
        JwtGrantedAuthoritiesConverter scopes = new JwtGrantedAuthoritiesConverter();   // lee "scp" -> SCOPE_*
        scopes.setAuthoritiesClaimName("scp");
        scopes.setAuthorityPrefix("SCOPE_");

        JwtAuthenticationConverter c = new JwtAuthenticationConverter();
        c.setJwtGrantedAuthoritiesConverter(jwt -> {
            var autoridades = new java.util.ArrayList<GrantedAuthority>(scopes.convert(jwt));
            var roles = jwt.getClaimAsStringList("roles");
            if (roles != null) roles.forEach(r -> autoridades.add(new SimpleGrantedAuthority("APPROLE_" + r)));
            return autoridades;
        });
        return c;
    }
}
// y en el filtro: .oauth2ResourceServer(o -> o.jwt(j -> j.jwtAuthenticationConverter(convertidor())))
```
> Nota: en Entra ID la claim `scp` viene como **una sola cadena** separada por espacios; `JwtGrantedAuthoritiesConverter` la divide por espacios por defecto.

## 2. Proteger tu API: Spring Boot reactivo (WebFlux)
```java
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.config.Customizer;
import org.springframework.security.config.annotation.web.reactive.EnableWebFluxSecurity;
import org.springframework.security.config.web.server.ServerHttpSecurity;
import org.springframework.security.web.server.SecurityWebFilterChain;

@Configuration
@EnableWebFluxSecurity
class SeguridadReactivaConfig {
    @Bean
    SecurityWebFilterChain filtro(ServerHttpSecurity http) {
        return http
            .authorizeExchange(a -> a
                .pathMatchers("/actuator/health/**").permitAll()
                .pathMatchers("/api/pedidos/**").hasAuthority("SCOPE_pedidos.read")
                .anyExchange().authenticated())
            .oauth2ResourceServer(o -> o.jwt(Customizer.withDefaults()))
            .build();
    }
    // Para la audiencia: ReactiveJwtDecoder con NimbusReactiveJwtDecoder.withIssuerLocation(...) y setJwtValidator(...)
}
```
Dependencias: `spring-boot-starter-webflux` y `spring-boot-starter-oauth2-resource-server`.

## 3. Proteger tu API: Quarkus (imperativo y reactivo)
Extensión `quarkus-oidc`:
```properties
quarkus.oidc.auth-server-url=https://login.microsoftonline.com/<TENANT_ID>/v2.0
quarkus.oidc.client-id=<CLIENT_ID_DE_LA_API>
quarkus.oidc.token.audience=api://<CLIENT_ID_DE_LA_API>
quarkus.oidc.application-type=service
```
```java
import io.quarkus.security.Authenticated;
import jakarta.annotation.security.RolesAllowed;
import jakarta.ws.rs.GET;
import jakarta.ws.rs.Path;

@Path("/api/pedidos")
public class PedidosResource {

    @GET
    @RolesAllowed("Catalogo.Read")     // toma las autoridades de la claim "roles" (configurable)
    public String listar() { return "ok"; }

    @GET @Path("/yo")
    @Authenticated
    public String yo(io.quarkus.security.identity.SecurityIdentity id) { return id.getPrincipal().getName(); }
}
```
Reactivo con RESTEasy Reactive: el mismo código puede devolver `Uni<String>` sin cambiar la seguridad.
> Con Entra ID, la claim de roles es `roles`; puede hacerse que `@RolesAllowed` la use con `quarkus.oidc.roles.role-claim-path=roles`. Verifica propiedades en la guía de OIDC de tu versión de Quarkus.

## 4. Llamar a otra API: client credentials con identidad administrada o MSAL
**Preferido en Azure: `azure-identity`** (sin secretos cuando corre en Azure):
```java
import com.azure.core.credential.TokenRequestContext;
import com.azure.identity.DefaultAzureCredentialBuilder;

var credencial = new DefaultAzureCredentialBuilder().build();
String token = credencial
        .getToken(new TokenRequestContext().addScopes("api://<CLIENT_ID_DE_LA_API_DESTINO>/.default"))
        .block()
        .getToken();
// Authorization: Bearer <token>
```
`DefaultAzureCredential` intenta: variables de entorno → workload identity → managed identity → Azure CLI (tu `az login` en local) → etc. Por eso el **mismo código** funciona en tu laptop y en Azure.

**Fuera de Azure o con secreto/certificado: MSAL4J**
```java
// dependencia: com.microsoft.azure:msal4j
import com.microsoft.aad.msal4j.ClientCredentialFactory;
import com.microsoft.aad.msal4j.ClientCredentialParameters;
import com.microsoft.aad.msal4j.ConfidentialClientApplication;
import com.microsoft.aad.msal4j.IClientCredential;
import java.util.Set;

class TokenConMsal {
    String obtenerToken() throws Exception {
        IClientCredential cred = ClientCredentialFactory.createFromSecret(System.getenv("CLIENT_SECRET"));
        ConfidentialClientApplication app = ConfidentialClientApplication
                .builder("<CLIENT_ID>", cred)
                .authority("https://login.microsoftonline.com/<TENANT_ID>/")
                .build();
        var resultado = app.acquireToken(ClientCredentialParameters.builder(Set.of("api://<API>/.default")).build()).join();
        return resultado.accessToken();
    }
}
```
> El secreto viene de una variable de entorno inyectada desde el vault, nunca del código. Preferible: certificado o credencial federada.

**Cachea el token** hasta poco antes de `exp`; no pidas uno por cada petición.

## 5. Qué NO hacer desde Java
- No decodificar el JWT "a mano" sin verificar la firma.
- No saltarte la validación de `aud`.
- No guardar tokens en logs.
- No usar el flujo de contraseña.
