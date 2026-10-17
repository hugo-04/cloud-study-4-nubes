# Transversal · Patrones de diseño · De comportamiento

Resuelven **cómo se reparten responsabilidades y se comunican los objetos**. Ejemplos en Java 21 con el dominio de ModaLima.

## 1. Chain of Responsibility
**Problema:** una petición pasa por varias validaciones/filtros y cada uno puede cortar (fraude, stock, límite de crédito).
**Solución:** una cadena de manejadores; cada uno decide si procesa, rechaza o pasa al siguiente.

```java
import java.util.List;
import java.util.Optional;

record Compra(String cliente, long total, int items) { }

interface Regla {
    Optional<String> rechazo(Compra c);   // vacío = pasa al siguiente
}

final class CadenaDeReglas {
    private final List<Regla> reglas;

    CadenaDeReglas(List<Regla> reglas) {
        this.reglas = List.copyOf(reglas);
    }

    Optional<String> evaluar(Compra c) {
        for (Regla r : reglas) {
            var x = r.rechazo(c);
            if (x.isPresent()) {
                return x;   // corta la cadena
            }
        }
        return Optional.empty();
    }

    static CadenaDeReglas porDefecto() {
        return new CadenaDeReglas(List.of(
            c -> c.items() > 50 ? Optional.of("demasiados ítems") : Optional.empty(),
            c -> c.total() > 5_000_000 ? Optional.of("revisión antifraude") : Optional.empty()));
    }
}
```
**En frameworks:** filtros de servlet, `SecurityFilterChain`, `WebFilter`, interceptores.

## 2. Command
**Problema:** encapsular una acción como objeto para encolarla, registrarla, reintentarla o deshacerla.
**Solución:** un objeto con `ejecutar()` (y opcionalmente `deshacer()`).

```java
import java.util.ArrayDeque;
import java.util.Deque;
import java.util.HashMap;
import java.util.Map;

interface Comando {
    void ejecutar();

    void deshacer();
}

class Stock {
    final Map<String, Integer> unidades = new HashMap<>(Map.of("SKU-1", 10));
}

record Reservar(Stock s, String sku, int n) implements Comando {
    public void ejecutar() {
        s.unidades.merge(sku, -n, Integer::sum);
    }

    public void deshacer() {
        s.unidades.merge(sku, n, Integer::sum);   // compensación (como en una saga)
    }
}

class Historial {
    private final Deque<Comando> hechos = new ArrayDeque<>();

    void correr(Comando c) {
        c.ejecutar();
        hechos.push(c);
    }

    void deshacerTodo() {
        while (!hechos.isEmpty()) {
            hechos.pop().deshacer();
        }
    }
}
```
**Cuándo sí:** colas de trabajo, *undo*, compensaciones, CQRS (los comandos del lado de escritura).

## 3. Interpreter
**Problema:** evaluar un pequeño lenguaje propio (reglas de promoción «categoria=zapatillas Y total>100000»).
**Solución:** una clase por regla gramatical que sabe evaluarse; el árbol se construye con un *parser* simple.

```java
import java.util.Map;

sealed interface Expr permits Igual, Mayor, Y {
    boolean evaluar(Map<String, String> ctx);
}

record Igual(String campo, String valor) implements Expr {
    public boolean evaluar(Map<String, String> ctx) {
        return valor.equals(ctx.get(campo));
    }
}

record Mayor(String campo, long valor) implements Expr {
    public boolean evaluar(Map<String, String> ctx) {
        return Long.parseLong(ctx.getOrDefault(campo, "0")) > valor;
    }
}

record Y(Expr a, Expr b) implements Expr {
    public boolean evaluar(Map<String, String> ctx) {
        return a.evaluar(ctx) && b.evaluar(ctx);
    }
}

final class ParserReglas {
    /** Gramática mínima: termino (" Y " termino)*, termino = campo=valor | campo>numero */
    static Expr parsear(String texto) {
        Expr r = null;
        for (String t : texto.split(" Y ")) {
            Expr e = t.contains(">") ? new Mayor(t.split(">")[0].trim(), Long.parseLong(t.split(">")[1].trim()))
                : new Igual(t.split("=")[0].trim(), t.split("=")[1].trim());
            r = r == null ? e : new Y(r, e);
        }
        return r;
    }
}
```
**Cuándo sí:** DSL pequeños y estables. **Cuándo no:** lenguajes complejos (usa un motor de reglas o un generador de *parsers*).

## 4. Iterator
**Problema:** recorrer una colección o una fuente paginada sin exponer cómo está hecha (API que devuelve páginas).
**Solución:** un objeto que entrega elementos uno a uno y oculta la paginación.

```java
import java.util.Iterator;
import java.util.List;
import java.util.NoSuchElementException;
import java.util.function.Function;

record Pagina<T>(List<T> elementos, String siguiente) { }

final class RecorridoPaginado<T> implements Iterator<T> {
    private final Function<String, Pagina<T>> pedirPagina;
    private Iterator<T> actual;
    private String token;
    private boolean fin;

    RecorridoPaginado(Function<String, Pagina<T>> pedirPagina) {
        this.pedirPagina = pedirPagina;
        cargar(null);
    }

    private void cargar(String t) {
        var p = pedirPagina.apply(t);
        actual = p.elementos().iterator();
        token = p.siguiente();
        fin = token == null;
    }

    public boolean hasNext() {
        while (!actual.hasNext() && !fin) {
            cargar(token);
        }
        return actual.hasNext();
    }

    public T next() {
        if (!hasNext()) {
            throw new NoSuchElementException();
        }
        return actual.next();
    }
}
```
**En Java:** `Iterable`, `Stream`, `Spliterator`; los SDK exponen `iterateAll()` justo así.

## 5. Mediator
**Problema:** muchos componentes que se hablan entre sí crean una red de dependencias (carrito, cupones, envío y totales se recalculan mutuamente).
**Solución:** un mediador central al que todos avisan; él coordina.

```java
import java.util.ArrayList;
import java.util.List;

interface Componente {
    void alCambiar(String evento, MediadorCarrito m);
}

class MediadorCarrito {
    private final List<Componente> componentes = new ArrayList<>();
    final List<String> registro = new ArrayList<>();
    long total;

    void registrar(Componente c) {
        componentes.add(c);
    }

    void avisar(String evento) {
        registro.add(evento);
        componentes.forEach(c -> c.alCambiar(evento, this));
    }
}

class Totales implements Componente {
    public void alCambiar(String evento, MediadorCarrito m) {
        if (evento.startsWith("item:")) {
            m.total += Long.parseLong(evento.substring(5));
        }
    }
}

class Cupones implements Componente {
    public void alCambiar(String evento, MediadorCarrito m) {
        if (evento.equals("cupon:DIEZ")) {
            m.total = m.total * 90 / 100;
        }
    }
}
```
**A nivel de sistema:** un orquestador de saga es un mediador. **Riesgo:** que el mediador se vuelva un «dios».

## 6. Memento
**Problema:** guardar y restaurar el estado de un objeto sin romper su encapsulamiento (borrador de un pedido que se puede revertir).
**Solución:** el objeto produce una instantánea opaca y sabe restaurarse desde ella.

```java
import java.util.ArrayList;
import java.util.List;

class Borrador {
    private final List<String> lineas = new ArrayList<>();
    private String nota = "";

    record Instantanea(List<String> lineas, String nota) { }

    void agregar(String l) {
        lineas.add(l);
    }

    void nota(String n) {
        nota = n;
    }

    Instantanea guardar() {
        return new Instantanea(List.copyOf(lineas), nota);
    }

    void restaurar(Instantanea i) {
        lineas.clear();
        lineas.addAll(i.lineas());
        nota = i.nota();
    }

    int cantidad() {
        return lineas.size();
    }
}
```
**Cuándo sí:** *undo*, puntos de control. **Relacionado:** *event sourcing* guarda la historia completa en vez de instantáneas (o ambas).

## 7. Observer
**Problema:** varios interesados deben enterarse de un cambio sin que el emisor los conozca (pedido pagado → correo, puntos, analítica).
**Solución:** el sujeto mantiene suscriptores y les notifica.

```java
import java.util.List;
import java.util.concurrent.CopyOnWriteArrayList;
import java.util.function.Consumer;

record PedidoPagadoEvento(String id, long total) { }

final class BusLocal {
    private final List<Consumer<PedidoPagadoEvento>> oyentes = new CopyOnWriteArrayList<>();

    Runnable suscribir(Consumer<PedidoPagadoEvento> o) {
        oyentes.add(o);
        return () -> oyentes.remove(o);   // permite desuscribirse
    }

    void publicar(PedidoPagadoEvento e) {
        for (var o : oyentes) {
            try {
                o.accept(e);
            } catch (RuntimeException ex) {
                // un oyente que falla no debe impedir a los demás
            }
        }
    }
}
```
**En frameworks:** `ApplicationEventPublisher` + `@EventListener` (Spring), `Event<T>` + `@Observes` (CDI). **Entre servicios:** se vuelve publicación de eventos con un broker (y entonces aplica outbox).

## 8. State
**Problema:** el comportamiento cambia según el estado y los `if (estado == …)` se multiplican (pedido: creado → pagado → enviado → entregado / cancelado).
**Solución:** un objeto por estado que define las transiciones válidas.

```java
sealed interface EstadoPedido permits Creado, Pagado, Enviado, Entregado, Cancelado {
    default EstadoPedido pagar() {
        throw new IllegalStateException("no se puede pagar en " + getClass().getSimpleName());
    }

    default EstadoPedido enviar() {
        throw new IllegalStateException("no se puede enviar en " + getClass().getSimpleName());
    }

    default EstadoPedido entregar() {
        throw new IllegalStateException("no se puede entregar en " + getClass().getSimpleName());
    }

    default EstadoPedido cancelar() {
        throw new IllegalStateException("no se puede cancelar en " + getClass().getSimpleName());
    }
}

record Creado() implements EstadoPedido {
    public EstadoPedido pagar() {
        return new Pagado();
    }

    public EstadoPedido cancelar() {
        return new Cancelado();
    }
}

record Pagado() implements EstadoPedido {
    public EstadoPedido enviar() {
        return new Enviado();
    }

    public EstadoPedido cancelar() {
        return new Cancelado();   // con reembolso
    }
}

record Enviado() implements EstadoPedido {
    public EstadoPedido entregar() {
        return new Entregado();
    }
}

record Entregado() implements EstadoPedido { }

record Cancelado() implements EstadoPedido { }
```
**Cuándo sí:** máquinas de estado de negocio. **Tip:** persiste el estado como texto y valida transiciones aquí, no en el controlador.

## 9. Strategy
**Problema:** varias formas intercambiables de hacer lo mismo (cálculo de envío: estándar, express, retiro en tienda).
**Solución:** una interfaz por algoritmo; el contexto recibe la estrategia.

```java
import java.util.Map;

@FunctionalInterface
interface CalculoEnvio {
    long costo(long subtotal, int pesoGramos);
}

final class Envios {
    static final Map<String, CalculoEnvio> ESTRATEGIAS = Map.of(
        "estandar", (s, p) -> s >= 150_000 ? 0 : 9_900 + p / 1000 * 1_000,
        "express", (s, p) -> 19_900 + p / 1000 * 2_000,
        "tienda", (s, p) -> 0);

    static long costo(String modo, long subtotal, int peso) {
        return ESTRATEGIAS.getOrDefault(modo, ESTRATEGIAS.get("estandar")).costo(subtotal, peso);
    }
}
```
**Diferencia con State:** la estrategia la elige el cliente; el estado cambia solo según las transiciones.

## 10. Template Method
**Problema:** varios procesos comparten los pasos y cambian solo algunos (importar catálogos de distintos proveedores: leer → validar → transformar → guardar).
**Solución:** una clase base con el algoritmo fijo y «ganchos» que las subclases implementan.

```java
import java.util.ArrayList;
import java.util.List;

abstract class ImportadorCatalogo {
    /** El esqueleto es final: el orden no se puede romper. */
    final List<String> importar(String origen) {
        var guardados = new ArrayList<String>();
        for (String fila : leer(origen)) {
            if (valida(fila)) {
                guardados.add(transformar(fila));
            }
        }
        return guardados;
    }

    protected abstract List<String> leer(String origen);

    protected boolean valida(String fila) {
        return !fila.isBlank();
    }

    protected abstract String transformar(String fila);
}

class ImportadorCsv extends ImportadorCatalogo {
    protected List<String> leer(String origen) {
        return List.of(origen.split("\n"));
    }

    protected String transformar(String fila) {
        return fila.split(";")[0].trim().toUpperCase();
    }
}
```
**Alternativa moderna:** composición con funciones (pasar `transformar` como lambda) evita herencia. **En frameworks:** `JdbcTemplate`, `RestTemplate` (callbacks).

## 11. Visitor
**Problema:** agregar operaciones nuevas (exportar, calcular impuestos) a una jerarquía estable sin tocar sus clases.
**Solución:** en Java 21, **`sealed` + `switch` con patrones** cumple el papel del Visitor clásico con verificación de exhaustividad.

```java
sealed interface LineaFactura permits LineaProducto, LineaEnvio, LineaDescuento { }

record LineaProducto(String sku, long monto) implements LineaFactura { }

record LineaEnvio(long monto) implements LineaFactura { }

record LineaDescuento(long monto) implements LineaFactura { }

final class Impuestos {
    /** Operación nueva sin tocar las clases; si se agrega un tipo, el compilador obliga a cubrirlo. */
    static long iva(LineaFactura l) {
        return switch (l) {
            case LineaProducto p -> p.monto() * 18 / 100;
            case LineaEnvio e -> e.monto() * 18 / 100;
            case LineaDescuento d -> -d.monto() * 18 / 100;
        };
    }

    static String exportar(LineaFactura l) {
        return switch (l) {
            case LineaProducto p -> "P;" + p.sku() + ";" + p.monto();
            case LineaEnvio e -> "E;" + e.monto();
            case LineaDescuento d -> "D;" + d.monto();
        };
    }
}
```
**Cuándo sí:** jerarquía cerrada, operaciones que crecen. **Cuándo no:** si la jerarquía cambia mucho (cada tipo nuevo toca todas las operaciones).

## Resumen
| Patrón | Pregunta | Señal de uso |
|---|---|---|
| Chain of Responsibility | ¿Quién maneja esto? | Filtros y validaciones en serie |
| Command | ¿Cómo encapsulo una acción? | Colas, *undo*, compensaciones |
| Interpreter | ¿Cómo evalúo mi mini-lenguaje? | Reglas configurables simples |
| Iterator | ¿Cómo recorro sin exponer estructura? | Paginación |
| Mediator | ¿Quién coordina a muchos? | Dependencias cruzadas |
| Memento | ¿Cómo guardo y restauro estado? | *Undo*, puntos de control |
| Observer | ¿Cómo aviso a interesados? | Eventos de dominio |
| State | ¿Cómo cambia el comportamiento por estado? | `if (estado ==…)` repetidos |
| Strategy | ¿Qué algoritmo uso? | Variantes intercambiables |
| Template Method | ¿Qué pasos son fijos? | Procesos con huecos |
| Visitor | ¿Cómo agrego operaciones a una jerarquía? | `sealed` + `switch` |
