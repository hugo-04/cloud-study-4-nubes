# Transversal · Testing · TDD, BDD y pruebas en microservicios

## 1. La pirámide (y el panal)
```
            ▲  pocas   E2E / de sistema        (lentas, frágiles, valiosas para flujos críticos)
           ▲▲▲         de contrato             (consumidor ↔ proveedor, sin levantar todo)
         ▲▲▲▲▲         de integración          (base real en contenedor, broker, HTTP)
      ▲▲▲▲▲▲▲▲▲  muchas unitarias              (dominio y casos de uso, milisegundos)
```
En microservicios se habla del «panal»: más peso en **integración** del servicio con sus dependencias reales (contenedores) y en **contrato**, menos en E2E entre todos los servicios.

| Tipo | Qué prueba | Herramienta típica |
|---|---|---|
| Unitaria | Una clase o regla, sin E/S | JUnit 5, AssertJ |
| Con dobles | Un caso de uso aislando puertos | Mockito |
| Integración | Adaptadores contra la tecnología real | Testcontainers, *slices* de Spring, `@QuarkusTest` |
| Contrato | Que proveedor y consumidor coinciden | Pact, Spring Cloud Contract |
| E2E | Un flujo de negocio completo | Pocas, en un entorno efímero |
| Arquitectura | Reglas de dependencias | ArchUnit |
| Mutación | Que las pruebas detectan errores | PIT |

## 2. Dobles de prueba
| Doble | Qué es | Ejemplo |
|---|---|---|
| **Dummy** | Se pasa pero no se usa | `null` o un objeto vacío |
| **Stub** | Respuestas fijas | `when(pasarela.autorizar(...)).thenReturn(true)` |
| **Fake** | Implementación real pero simple | Repositorio en memoria |
| **Spy** | Registra cómo se usó | `verify(repo).guardar(any())` |
| **Mock** | Stub + expectativas verificadas | Mockito |

Regla: **fakes para tus puertos** (repositorio en memoria) y **mocks para verificar interacciones importantes** (no se cobró si no hay stock). No mockees lo que no es tuyo (SDK): envuélvelo en un adaptador y prueba el adaptador con integración.

## 3. TDD: rojo → verde → refactor
Ejemplo: regla de descuentos de ModaLima — «10 % desde 3 unidades; 20 % desde 10; nunca más de 50 000 céntimos de descuento».

**Paso 1 (rojo):** escribe la prueba que falla.
**Paso 2 (verde):** el código mínimo que la pasa.
**Paso 3 (refactor):** limpia sin cambiar comportamiento; las pruebas te cuidan.

```java
// (clase reutilizada en los bloques siguientes)
/** Resultado tras varios ciclos de TDD: cada regla nació de una prueba. */
final class CalculadoraDescuentos {
    static final long TOPE = 50_000;

    static long descuento(int unidades, long subtotal) {
        if (unidades < 0 || subtotal < 0) {
            throw new IllegalArgumentException("valores negativos");
        }
        int pct = unidades >= 10 ? 20 : unidades >= 3 ? 10 : 0;
        return Math.min(subtotal * pct / 100, TOPE);
    }
}
```

```java
import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.CsvSource;

class CalculadoraDescuentosTest {

    @ParameterizedTest(name = "{0} unidades, subtotal {1} → {2}")
    @CsvSource({
        "1, 10000, 0",        // ciclo 1: sin descuento
        "3, 10000, 1000",     // ciclo 2: 10 % desde 3
        "10, 10000, 2000",    // ciclo 3: 20 % desde 10
        "10, 1000000, 50000"  // ciclo 4: tope
    })
    void reglas(int unidades, long subtotal, long esperado) {
        assertThat(CalculadoraDescuentos.descuento(unidades, subtotal)).isEqualTo(esperado);
    }

    @Test
    void rechazaNegativos() {
        assertThatThrownBy(() -> CalculadoraDescuentos.descuento(-1, 100)).isInstanceOf(IllegalArgumentException.class);
    }
}
```

## 4. Caso de uso con Mockito (puertos como dobles)
```java
// (clase reutilizada en los bloques siguientes)
interface Stock {
    boolean reservar(String sku, int n);
}

interface Cobros {
    String cobrar(String cliente, long total);
}

final class Comprar {
    private final Stock stock;
    private final Cobros cobros;

    Comprar(Stock stock, Cobros cobros) {
        this.stock = stock;
        this.cobros = cobros;
    }

    String ejecutar(String cliente, String sku, int n, long precio) {
        if (!stock.reservar(sku, n)) {
            return "SIN_STOCK";
        }
        long subtotal = precio * n;
        return cobros.cobrar(cliente, subtotal - CalculadoraDescuentos.descuento(n, subtotal));
    }
}
```

```java
import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import org.junit.jupiter.api.Test;

class ComprarTest {
    private final Stock stock = mock(Stock.class);
    private final Cobros cobros = mock(Cobros.class);
    private final Comprar comprar = new Comprar(stock, cobros);

    @Test
    void sinStockNoCobra() {
        when(stock.reservar("SKU-1", 2)).thenReturn(false);
        assertThat(comprar.ejecutar("ana", "SKU-1", 2, 1000)).isEqualTo("SIN_STOCK");
        verify(cobros, never()).cobrar(anyString(), anyLong());   // la interacción que importa
    }

    @Test
    void cobraConDescuento() {
        when(stock.reservar("SKU-1", 3)).thenReturn(true);
        when(cobros.cobrar("ana", 2700)).thenReturn("pago-1");
        assertThat(comprar.ejecutar("ana", "SKU-1", 3, 1000)).isEqualTo("pago-1");
    }
}
```

## 5. BDD: comportamiento en lenguaje del negocio
Se escribe el escenario con negocio (Gherkin) y se automatiza con *step definitions*. Sirve para **acordar** reglas; no reemplaza a las unitarias.

```gherkin
# src/test/resources/compras.feature
Característica: Descuentos por volumen
  Escenario: Compra de 3 unidades con descuento
    Dado un producto "SKU-1" con precio 1000 y stock disponible
    Cuando "ana" compra 3 unidades
    Entonces se cobra 2700
```

```java
import static org.assertj.core.api.Assertions.assertThat;

import io.cucumber.java.es.Cuando;
import io.cucumber.java.es.Dado;
import io.cucumber.java.es.Entonces;
import java.util.concurrent.atomic.AtomicLong;

class PasosCompras {
    private final AtomicLong cobrado = new AtomicLong();
    private long precio;
    private Comprar comprar;

    @Dado("un producto {string} con precio {long} y stock disponible")
    public void producto(String sku, long precio) {
        this.precio = precio;
        this.comprar = new Comprar((s, n) -> true, (cliente, total) -> {
            cobrado.set(total);
            return "ok";
        });
    }

    @Cuando("{string} compra {int} unidades")
    public void compra(String cliente, int n) {
        comprar.ejecutar(cliente, "SKU-1", n, precio);
    }

    @Entonces("se cobra {long}")
    public void seCobra(long esperado) {
        assertThat(cobrado.get()).isEqualTo(esperado);
    }
}
```

## 6. Reglas de arquitectura con ArchUnit
```java
import static com.tngtech.archunit.lang.syntax.ArchRuleDefinition.noClasses;
import static com.tngtech.archunit.library.dependencies.SlicesRuleDefinition.slices;

import com.tngtech.archunit.core.importer.ClassFileImporter;
import org.junit.jupiter.api.Test;

class ReglasDeArquitecturaTest {
    private final com.tngtech.archunit.core.domain.JavaClasses clases =
        new ClassFileImporter().importPackages("com.modalima.tienda");

    @Test
    void elDominioNoDependeDeAdaptadoresNiFrameworks() {
        noClasses().that().resideInAPackage("..dominio..")
            .should().dependOnClassesThat().resideInAnyPackage("..adaptadores..", "org.springframework..", "jakarta.persistence..")
            .allowEmptyShould(true)
            .check(clases);
    }

    @Test
    void sinCiclosEntreModulos() {
        slices().matching("com.modalima.tienda.(*)..").should().beFreeOfCycles().allowEmptyShould(true).check(clases);
    }
}
```

## 7. Integración y contrato (esquema)
```java
// nocheck — requiere Testcontainers y un motor de contenedores
@SpringBootTest
@Testcontainers
class RepositorioPedidosIT {
    @Container
    @ServiceConnection
    static PostgreSQLContainer<?> db = new PostgreSQLContainer<>("postgres:17");

    @Autowired
    PedidoJpa repo;

    @Test
    void guardaYLeeConLineas() { /* … contra PostgreSQL real, con migraciones aplicadas … */ }
}
```
- **Contrato:** el consumidor publica lo que espera (`GET /v1/pedidos/{id}` devuelve `id`, `estado`); el proveedor verifica ese contrato en su CI antes de desplegar.
- **Mutación (PIT):** cambia el código (`>=` por `>`) y comprueba que alguna prueba falle; la cobertura sola no lo garantiza.

## 8. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Muchas unitarias rápidas del dominio | Probar todo por la API con el servicio levantado |
| Fakes para puertos propios | Mockear SDKs ajenos |
| Integración con la tecnología real (contenedores) | H2 «compatible» que esconde diferencias |
| Nombres de prueba que cuentan la regla | `test1`, `testOk` |
| Pruebas de contrato entre servicios | E2E de 15 servicios para cada cambio |
| Reglas de arquitectura en CI | Confiar en revisiones manuales |
| Medir mutación en el dominio crítico | Perseguir 100 % de cobertura |

## Casos reales
| Historia | Qué pasó | Lección |
|---|---|---|
| Verde en H2, rojo en producción | Una consulta de ModaLima con `jsonb` pasaba en H2 y fallaba en PostgreSQL | Integración con la base real en contenedor |
| El mock que mentía | Café Andino mockeó el SDK de pagos con un formato de error que nunca existió | Adaptador propio + prueba de integración/contrato |
| Cobertura 95 %, error en producción | Las pruebas no tenían aserciones relevantes | Mutación y aserciones de negocio |
| El dominio con anotaciones JPA | Cambiar de base obligó a tocar reglas de negocio | Hexagonal + ArchUnit |
