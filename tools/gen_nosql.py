import genlib
CAR = '''
import java.math.BigDecimal;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/** El carrito como valor inmutable y su conversión a fila. Puro. */
public record Carrito(String idCliente, Map<String, Integer> items, BigDecimal total) {

    public static final int MAX_ITEMS = 50;

    public static Carrito vacio(String idCliente) {
        if (idCliente == null || !idCliente.matches("C-[0-9]{1,12}")) {
            throw new IllegalArgumentException("idCliente inválido");
        }
        return new Carrito(idCliente, Map.of(), BigDecimal.ZERO);
    }

    public Carrito agregar(String sku, int cantidad, BigDecimal precio) {
        if (cantidad < 1 || cantidad > 10 || precio.signum() <= 0) {
            throw new IllegalArgumentException("cantidad 1..10 y precio positivo");
        }
        var nuevos = new LinkedHashMap<>(items);
        nuevos.merge(sku, cantidad, Integer::sum);
        if (nuevos.size() > MAX_ITEMS || nuevos.get(sku) > 10) {
            throw new IllegalStateException("límite del carrito alcanzado");
        }
        return new Carrito(idCliente, Map.copyOf(nuevos), total.add(precio.multiply(BigDecimal.valueOf(cantidad))));
    }

    public Map<String, Object> aFila() {
        var lineas = items.entrySet().stream().map(e -> Map.<String, Object>of("sku", e.getKey(), "cantidad", e.getValue())).toList();
        return Map.of("id_cliente", idCliente, "id_carrito", "actual", "items", lineas, "total", total);
    }

    @SuppressWarnings("unchecked")
    public static Carrito deFila(Map<String, Object> fila) {
        var items = new LinkedHashMap<String, Integer>();
        for (Object o : (List<Object>) fila.getOrDefault("items", List.of())) {
            var m = (Map<String, Object>) o;
            items.put((String) m.get("sku"), ((Number) m.get("cantidad")).intValue());
        }
        return new Carrito((String) fila.get("id_cliente"), Map.copyOf(items), new BigDecimal(fila.get("total").toString()));
    }
}
'''
SDK = '''
import com.oracle.bmc.nosql.NosqlClient;
import com.oracle.bmc.nosql.model.UpdateRowDetails;
import com.oracle.bmc.nosql.requests.GetRowRequest;
import com.oracle.bmc.nosql.requests.UpdateRowRequest;
import java.util.List;
import java.util.Map;
import java.util.Optional;

/** Adaptador del SDK: lectura por clave y escritura condicional por versión. */
public class CarritosOci implements AutoCloseable {

    public record Leido(Map<String, Object> fila, String version) { }

    private final NosqlClient cliente;
    private final String compartimentoId;

    public CarritosOci(NosqlClient cliente, String compartimentoId) {
        this.cliente = cliente;
        this.compartimentoId = compartimentoId;
    }

    public Optional<Leido> leer(String idCliente) {
        var r = cliente.getRow(GetRowRequest.builder().tableNameOrId("carritos").compartmentId(compartimentoId)
            .key(List.of("id_cliente:" + idCliente, "id_carrito:actual")).build());
        var fila = r.getRow().getValue();
        // el etag de la respuesta es la versión de la fila: se usa en ifMatch al escribir
        return fila == null || fila.isEmpty() ? Optional.empty() : Optional.of(new Leido(fila, r.getEtag()));
    }

    /** versionEsperada == null ⇒ solo si no existe. Devuelve false si otro escribió antes. */
    public boolean guardar(Map<String, Object> fila, String versionEsperada) {
        var det = UpdateRowDetails.builder().compartmentId(compartimentoId).value(fila).isTtlUseTableDefault(true);
        var req = UpdateRowRequest.builder().tableNameOrId("carritos");
        if (versionEsperada == null) {
            det.option(UpdateRowDetails.Option.IfAbsent);
        } else {
            req.ifMatch(versionEsperada);
        }
        return cliente.updateRow(req.updateRowDetails(det.build()).build()).getUpdateRowResult().getVersion() != null;
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.math.BigDecimal;

public class ServicioDeCarritos {

    public record Linea(String sku, int cantidad, BigDecimal precio) { }

    private final CarritosOci carritos;

    public ServicioDeCarritos(CarritosOci carritos) {
        this.carritos = carritos;
    }

    /** Concurrencia optimista: leer, modificar, escribir si nadie cambió la fila; si no, reintentar. */
    public Carrito agregar(String idCliente, Linea l) {
        for (int intento = 0; intento < 5; intento++) {
            var leido = carritos.leer(idCliente);
            var actual = leido.map(x -> Carrito.deFila(x.fila())).orElse(Carrito.vacio(idCliente));
            var nuevo = actual.agregar(l.sku(), l.cantidad(), l.precio());
            if (carritos.guardar(nuevo.aFila(), leido.map(CarritosOci.Leido::version).orElse(null))) {
                return nuevo;
            }
        }
        throw new IllegalStateException("conflicto persistente en el carrito " + idCliente);
    }
}
'''
genlib.oci('oci/08-datos/nosql', 'Datos · NoSQL',
  'Un **carrito con concurrencia optimista**: el carrito es un valor inmutable con reglas (límites de ítems y cantidades) y conversión a fila; el adaptador lee por clave completa (`id_cliente`, `id_carrito`) con `NosqlClient.getRow` y escribe de forma **condicional** (`IfAbsent` si es nuevo, `ifMatch` con la versión si existe), y el servicio reintenta si otra pestaña escribió antes. El TTL de la tabla limpia los carritos abandonados.',
  [('nosql.compartimento', 'ocid1.compartment.oc1..aaaa')],
  [('El carrito (lógica pura)', CAR, True), ('Adaptador del SDK', SDK, True), ('Servicio', SERV, True)],
  'Carritos', '/datos/carritos', 'ServicioDeCarritos', 'CarritosOci',
  ['import com.oracle.bmc.nosql.NosqlClient;'],
  'return new CarritosOci(NosqlClient.builder().region(Region.fromRegionId(region)).build(auth), compartimento);',
  [dict(n='agregar', v='POST', p='/{cliente}', args=[('String', 'cliente', 'p'), ('ServicioDeCarritos.Linea', 'l', 'b')], ret='Carrito', call='s.agregar(cliente, l)')],
  [('Leer y escribir filas del carrito', "`Allow dynamic-group app-tienda to use nosql-rows in compartment tienda-prod where target.nosql-table.name = 'carritos'`")],
  ['No hagas leer-modificar-escribir sin condición de versión.',
   'No uses `query` sin clave en el camino de cada petición.',
   'No guardes el carrito sin TTL.',
   'No pidas consistencia absoluta donde no hace falta.'])
