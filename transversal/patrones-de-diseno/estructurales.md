# Transversal · Patrones de diseño · Estructurales

Resuelven **cómo se componen clases y objetos** para formar estructuras mayores sin acoplarse. Ejemplos en Java 21 con el dominio de ModaLima.

## 1. Adapter
**Problema:** una biblioteca o sistema externo tiene una interfaz distinta a la que tu dominio espera (el ERP devuelve stock en XML con unidades en cajas).
**Solución:** una clase que implementa **tu** interfaz y traduce hacia la otra. Es el «adaptador» de la arquitectura hexagonal.

```java
interface Inventario {
    int unidadesDisponibles(String sku);
}

/** API ajena (no la controlas). */
class ErpLegado {
    String consultarStockXml(String codigo) {
        return "<stock codigo='" + codigo + "' cajas='3' porCaja='12'/>";
    }
}

class InventarioDesdeErp implements Inventario {
    private final ErpLegado erp;

    InventarioDesdeErp(ErpLegado erp) {
        this.erp = erp;
    }

    public int unidadesDisponibles(String sku) {
        String x = erp.consultarStockXml(sku);
        int cajas = Integer.parseInt(x.replaceAll(".*cajas='(\\d+)'.*", "$1"));
        int porCaja = Integer.parseInt(x.replaceAll(".*porCaja='(\\d+)'.*", "$1"));
        return cajas * porCaja;   // traducción de unidades: el dominio no sabe de cajas
    }
}
```
**Cuándo sí:** integrar SDKs, sistemas legados, proveedores. **Cuándo no:** si puedes cambiar la otra interfaz.

## 2. Bridge
**Problema:** dos dimensiones que varían independientemente (tipo de notificación × canal de envío) y la herencia explota en combinaciones.
**Solución:** separar la abstracción (qué se notifica) de la implementación (cómo se envía) y unirlas por composición.

```java
interface Canal {
    String enviar(String destino, String texto);
}

class CanalCorreo implements Canal {
    public String enviar(String d, String t) {
        return "correo a " + d + ": " + t;
    }
}

class CanalSms implements Canal {
    public String enviar(String d, String t) {
        return "sms a " + d + ": " + t;
    }
}

abstract class Notificacion {
    protected final Canal canal;

    Notificacion(Canal canal) {
        this.canal = canal;
    }

    abstract String notificar(String destino);
}

class AvisoDespacho extends Notificacion {
    private final String pedido;

    AvisoDespacho(Canal canal, String pedido) {
        super(canal);
        this.pedido = pedido;
    }

    String notificar(String destino) {
        return canal.enviar(destino, "Tu pedido " + pedido + " salió");
    }
}
```
**Cuándo sí:** N × M combinaciones. **Cuándo no:** una sola dimensión de variación.

## 3. Composite
**Problema:** tratar igual a elementos simples y a grupos (un producto o un *pack* de productos con precio).
**Solución:** una interfaz común; el compuesto contiene hijos y delega.

```java
import java.util.List;

sealed interface Articulo permits Producto, Pack {
    long precio();
}

record Producto(String sku, long precio) implements Articulo { }

record Pack(String nombre, List<Articulo> contenido, int descuentoPct) implements Articulo {
    public long precio() {
        long suma = contenido.stream().mapToLong(Articulo::precio).sum();
        return suma * (100 - descuentoPct) / 100;   // un pack puede contener otros packs
    }
}
```
**Cuándo sí:** jerarquías (categorías, menús, reglas anidadas). **Cuándo no:** listas planas.

## 4. Decorator
**Problema:** agregar comportamiento (caché, métricas, reintentos) a un objeto sin modificarlo ni crear subclases por combinación.
**Solución:** envolver el objeto en otro que implementa la misma interfaz y agrega algo antes/después.

```java
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

interface Catalogo {
    String ficha(String sku);
}

class CatalogoConCache implements Catalogo {
    private final Catalogo base;
    private final Map<String, String> cache = new ConcurrentHashMap<>();

    CatalogoConCache(Catalogo base) {
        this.base = base;
    }

    public String ficha(String sku) {
        return cache.computeIfAbsent(sku, base::ficha);
    }
}

class CatalogoMedido implements Catalogo {
    private final Catalogo base;
    final AtomicLong llamadas = new AtomicLong();

    CatalogoMedido(Catalogo base) {
        this.base = base;
    }

    public String ficha(String sku) {
        llamadas.incrementAndGet();
        return base.ficha(sku);
    }
}
// uso: new CatalogoConCache(new CatalogoMedido(catalogoReal)) — el orden de las capas importa
```
**Cuándo sí:** responsabilidades transversales combinables. **En frameworks:** filtros HTTP, interceptores, AOP (`@Transactional`, `@Cacheable` son decoradores generados).

## 5. Facade
**Problema:** un subsistema con muchas piezas (inventario, pagos, envíos) que el cliente no debería orquestar.
**Solución:** una fachada con operaciones de alto nivel.

```java
class ServicioStock {
    boolean reservar(String sku, int n) {
        return n <= 10;
    }
}

class ServicioPago {
    String cobrar(String cliente, long total) {
        return "pago-" + cliente + "-" + total;
    }
}

class ServicioEnvio {
    String programar(String cliente) {
        return "envio-" + cliente;
    }
}

class FachadaCompra {
    private final ServicioStock stock = new ServicioStock();
    private final ServicioPago pago = new ServicioPago();
    private final ServicioEnvio envio = new ServicioEnvio();

    String comprar(String cliente, String sku, int n, long total) {
        if (!stock.reservar(sku, n)) {
            return "SIN_STOCK";
        }
        return pago.cobrar(cliente, total) + "/" + envio.programar(cliente);
    }
}
```
**Cuándo sí:** simplificar el uso de un subsistema; BFF y API Gateway son fachadas a nivel de sistema. **Cuándo no:** si se vuelve un «objeto dios» con toda la lógica.

## 6. Flyweight
**Problema:** millones de objetos con mucha información repetida (cada línea de clickstream repite datos del producto).
**Solución:** compartir la parte intrínseca inmutable (ficha del producto) y guardar aparte la extrínseca (sesión, hora).

```java
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

record FichaProducto(String sku, String categoria, String marca) { }

final class FichasCompartidas {
    private static final Map<String, FichaProducto> POOL = new ConcurrentHashMap<>();

    static FichaProducto de(String sku, String categoria, String marca) {
        return POOL.computeIfAbsent(sku, k -> new FichaProducto(sku, categoria, marca));
    }

    static int tamano() {
        return POOL.size();
    }
}

record Click(String sesion, Instant momento, FichaProducto ficha) { }   // la ficha se comparte entre millones de clics
```
**Cuándo sí:** memoria dominada por datos repetidos. **Cuándo no:** pocos objetos; complica sin beneficio. **En Java:** `Integer.valueOf` cachea pequeños, `String.intern`.

## 7. Proxy
**Problema:** controlar el acceso a un objeto (permisos, carga perezosa, llamada remota) sin que el cliente lo note.
**Solución:** un sustituto con la misma interfaz que decide cuándo y si delegar.

```java
import java.util.Set;
import java.util.function.Supplier;

interface Reportes {
    String ventasDelDia();
}

class ReportesProtegidos implements Reportes {
    private final Supplier<Reportes> real;     // perezoso: se crea solo si se usa
    private final Set<String> rolesUsuario;
    private Reportes instancia;

    ReportesProtegidos(Supplier<Reportes> real, Set<String> rolesUsuario) {
        this.real = real;
        this.rolesUsuario = rolesUsuario;
    }

    public String ventasDelDia() {
        if (!rolesUsuario.contains("finanzas")) {
            throw new SecurityException("requiere rol finanzas");
        }
        if (instancia == null) {
            instancia = real.get();
        }
        return instancia.ventasDelDia();
    }
}
```
**Diferencia con Decorator:** el proxy **controla el acceso**; el decorador **agrega comportamiento**. **En frameworks:** proxies de Spring AOP, entidades perezosas de Hibernate, clientes REST declarativos.

## Resumen
| Patrón | Pregunta | Señal de uso |
|---|---|---|
| Adapter | ¿Cómo encajo una interfaz ajena? | Integración con terceros |
| Bridge | ¿Cómo separo dos dimensiones? | Explosión de subclases |
| Composite | ¿Cómo trato igual uno y muchos? | Árboles |
| Decorator | ¿Cómo agrego comportamiento apilable? | Caché, métricas, reintentos |
| Facade | ¿Cómo simplifico un subsistema? | Clientes que orquestan demasiado |
| Flyweight | ¿Cómo comparto datos repetidos? | Memoria alta por duplicados |
| Proxy | ¿Cómo controlo el acceso? | Permisos, carga perezosa, remoto |
