# Transversal · Patrones de diseño · Creacionales

Resuelven **cómo se crean los objetos** sin acoplar al cliente a clases concretas. Ejemplos en Java 21 con el dominio de ModaLima.

## 1. Factory Method
**Problema:** el código que usa un objeto no debería decidir qué clase concreta crear (pasarela de pago según país).
**Solución:** un método (o una interfaz de fábrica) que devuelve la abstracción; las subclases o implementaciones eligen la clase.

```java
import java.util.Map;
import java.util.function.Supplier;

interface Pasarela {
    String cobrar(long centimos);
}

class PasarelaTarjeta implements Pasarela {
    public String cobrar(long c) {
        return "tarjeta:" + c;
    }
}

class PasarelaTransferencia implements Pasarela {
    public String cobrar(long c) {
        return "transferencia:" + c;
    }
}

/** Fábrica registrable: agregar un medio de pago no toca a los clientes (abierto/cerrado). */
final class FabricaPasarelas {
    private static final Map<String, Supplier<Pasarela>> REGISTRO = Map.of(
        "tarjeta", PasarelaTarjeta::new,
        "transferencia", PasarelaTransferencia::new);

    static Pasarela para(String medio) {
        var s = REGISTRO.get(medio);
        if (s == null) {
            throw new IllegalArgumentException("medio no soportado: " + medio);
        }
        return s.get();
    }
}
```
**Cuándo sí:** varias implementaciones elegidas en tiempo de ejecución. **Cuándo no:** una sola implementación (YAGNI). **En frameworks:** `@Bean` en Spring, productores `@Produces` en CDI.

## 2. Abstract Factory
**Problema:** crear **familias** de objetos que deben ir juntos (cliente HTTP + serializador + firma para un mismo proveedor de envíos).
**Solución:** una interfaz con un método de creación por producto; cada familia la implementa.

```java
interface ClienteEnvios {
    String cotizar(String destino);
}

interface EtiquetaEnvio {
    String generar(String pedido);
}

interface FabricaEnvios {
    ClienteEnvios cliente();

    EtiquetaEnvio etiqueta();
}

class FabricaCourierRapido implements FabricaEnvios {
    public ClienteEnvios cliente() {
        return d -> "rapido:" + d + ":24h";
    }

    public EtiquetaEnvio etiqueta() {
        return p -> "RAP-" + p;
    }
}

class FabricaCourierEconomico implements FabricaEnvios {
    public ClienteEnvios cliente() {
        return d -> "economico:" + d + ":72h";
    }

    public EtiquetaEnvio etiqueta() {
        return p -> "ECO-" + p;
    }
}

class Despacho {
    private final FabricaEnvios f;

    Despacho(FabricaEnvios f) {
        this.f = f;
    }

    String despachar(String pedido, String destino) {
        return f.cliente().cotizar(destino) + " " + f.etiqueta().generar(pedido);   // siempre de la misma familia
    }
}
```
**Cuándo sí:** familias intercambiables y coherentes. **Cuándo no:** si los productos no tienen que combinarse; basta Factory Method.

## 3. Builder
**Problema:** objetos con muchos campos opcionales y reglas (un pedido con descuentos, envío y notas) sin constructores de 10 parámetros.
**Solución:** un constructor paso a paso que valida al final y entrega un objeto inmutable.

```java
import java.util.ArrayList;
import java.util.List;

record PedidoArmado(String cliente, List<String> skus, String cupon, boolean regalo) {

    static Builder para(String cliente) {
        return new Builder(cliente);
    }

    static final class Builder {
        private final String cliente;
        private final List<String> skus = new ArrayList<>();
        private String cupon;
        private boolean regalo;

        private Builder(String cliente) {
            this.cliente = cliente;
        }

        Builder sku(String s) {
            skus.add(s);
            return this;
        }

        Builder cupon(String c) {
            this.cupon = c;
            return this;
        }

        Builder regalo() {
            this.regalo = true;
            return this;
        }

        PedidoArmado build() {
            if (skus.isEmpty()) {
                throw new IllegalStateException("un pedido necesita al menos un SKU");
            }
            return new PedidoArmado(cliente, List.copyOf(skus), cupon, regalo);
        }
    }
}
```
**Cuándo sí:** muchos opcionales, objetos inmutables, DSLs de prueba (*test data builders*). **Cuándo no:** 2–3 campos: un record basta. **En frameworks:** `RestClient.builder()`, `WebClient.builder()`, *builders* de los SDK.

## 4. Prototype
**Problema:** crear objetos costosos de inicializar copiando uno ya configurado (plantillas de campaña).
**Solución:** clonar un prototipo y ajustar lo distinto (en Java moderno: constructores de copia o *withers* en records, no `Cloneable`).

```java
import java.util.List;
import java.util.Map;

record Campana(String nombre, List<String> canales, Map<String, String> textos, int descuento) {

    Campana conNombre(String n) {
        return new Campana(n, canales, textos, descuento);
    }

    Campana conDescuento(int d) {
        return new Campana(nombre, canales, textos, d);
    }
}

final class Plantillas {
    static final Campana TEMPORADA = new Campana("plantilla", List.of("correo", "push"),
        Map.of("asunto", "Nueva temporada", "cuerpo", "Descubre la colección"), 10);

    static Campana cyber(int descuento) {
        return TEMPORADA.conNombre("cyber").conDescuento(descuento);   // copia inmutable, sin compartir estado mutable
    }
}
```
**Cuándo sí:** configuración base compleja y variantes. **Cuándo no:** objetos simples; evita `clone()` (copias superficiales sorpresivas).

## 5. Singleton
**Problema:** una sola instancia compartida (pool de conexiones, cliente de un SDK, registro de métricas).
**Solución:** en aplicaciones con contenedor, **déjalo al contenedor** (`@Singleton`/`@ApplicationScoped`, beans de Spring son *singleton* por defecto). Si no hay contenedor, `enum` o *holder* perezoso.

```java
import java.util.concurrent.atomic.AtomicLong;

/** Singleton sin contenedor: enum (seguro con hilos y serialización). */
enum ContadorGlobal {
    INSTANCIA;

    private final AtomicLong valor = new AtomicLong();

    long siguiente() {
        return valor.incrementAndGet();
    }
}

/** Holder perezoso: se crea al primer uso, sin sincronización explícita. */
final class ClienteCostoso {
    private ClienteCostoso() {
    }

    private static final class Holder {
        static final ClienteCostoso INSTANCIA = new ClienteCostoso();
    }

    static ClienteCostoso instancia() {
        return Holder.INSTANCIA;
    }
}
```
**Cuándo sí:** recursos caros y sin estado por petición. **Cuándo no:** como «variable global» con estado mutable: dificulta pruebas y concurrencia. En microservicios, recuerda que hay **N réplicas**: un singleton es único por proceso, no en el sistema.

## Resumen
| Patrón | Pregunta | Señal de uso |
|---|---|---|
| Factory Method | ¿Qué clase creo? | `switch` por tipo repetido en varios lugares |
| Abstract Factory | ¿Qué familia creo? | Objetos que deben combinarse |
| Builder | ¿Cómo armo algo complejo? | Constructores largos, muchos opcionales |
| Prototype | ¿Copio algo ya configurado? | Plantillas con variantes |
| Singleton | ¿Una sola instancia? | Recurso compartido (mejor: el contenedor) |
