import ggen
SIM = '''
import java.util.List;
import java.util.Optional;

/** Simula el URL map: host → path matcher → regla de ruta más específica → servicio. Puro. */
public class SimuladorDeUrlMap {

    public record ReglaHost(List<String> hosts, String matcher) { }

    public record ReglaRuta(List<String> rutas, String servicio) { }

    public record Matcher(String nombre, String servicioPorDefecto, List<ReglaRuta> reglas) { }

    public record Mapa(String servicioPorDefecto, List<ReglaHost> hosts, List<Matcher> matchers) { }

    public record Prueba(String host, String ruta, String servicioEsperado) { }

    public record ResultadoPrueba(Prueba prueba, String obtenido, boolean ok) { }

    public String resolver(Mapa m, String host, String ruta) {
        Optional<String> matcher = m.hosts().stream()
            .filter(h -> h.hosts().stream().anyMatch(x -> coincideHost(x, host)))
            .map(ReglaHost::matcher).findFirst();
        if (matcher.isEmpty()) {
            return m.servicioPorDefecto();
        }
        Matcher pm = m.matchers().stream().filter(x -> x.nombre().equals(matcher.get())).findFirst().orElseThrow();
        String mejor = null;
        int largo = -1;
        for (ReglaRuta r : pm.reglas()) {
            for (String p : r.rutas()) {
                int l = coincideRuta(p, ruta);
                if (l > largo) {
                    largo = l;
                    mejor = r.servicio();
                }
            }
        }
        return mejor != null ? mejor : pm.servicioPorDefecto();
    }

    public List<ResultadoPrueba> probar(Mapa m, List<Prueba> pruebas) {
        return pruebas.stream().map(p -> {
            String s = resolver(m, p.host(), p.ruta());
            return new ResultadoPrueba(p, s, s.endsWith(p.servicioEsperado()));
        }).toList();
    }

    static boolean coincideHost(String patron, String host) {
        return patron.equals("*") || patron.equals(host) || (patron.startsWith("*.") && host.endsWith(patron.substring(1)));
    }

    /** Devuelve la longitud de coincidencia (o -1). «/api/*» coincide con «/api/...»; sin «*», exacta. */
    static int coincideRuta(String patron, String ruta) {
        if (patron.endsWith("/*")) {
            String base = patron.substring(0, patron.length() - 1);
            return ruta.startsWith(base) || ruta.equals(base.substring(0, base.length() - 1)) ? base.length() : -1;
        }
        return patron.equals(ruta) ? patron.length() + 1000 : -1; // exacta gana a prefijo
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.compute.v1.UrlMapsClient;
import com.google.cloud.compute.v1.UrlMapsSettings;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.util.List;

/** Adaptador: convierte el URL map real (global) al modelo del simulador. */
public class UrlMapsGcp implements AutoCloseable {

    private final UrlMapsClient cliente;
    private final String proyecto;

    public UrlMapsGcp(GoogleCredentials cred, String proyecto) {
        try {
            this.cliente = UrlMapsClient.create(UrlMapsSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.proyecto = proyecto;
    }

    public SimuladorDeUrlMap.Mapa leer(String nombre) {
        var u = cliente.get(proyecto, nombre);
        var hosts = u.getHostRulesList().stream()
            .map(h -> new SimuladorDeUrlMap.ReglaHost(List.copyOf(h.getHostsList()), h.getPathMatcher())).toList();
        var matchers = u.getPathMatchersList().stream().map(pm -> new SimuladorDeUrlMap.Matcher(pm.getName(), pm.getDefaultService(),
            pm.getPathRulesList().stream().map(r -> new SimuladorDeUrlMap.ReglaRuta(List.copyOf(r.getPathsList()), r.getService())).toList()))
            .toList();
        return new SimuladorDeUrlMap.Mapa(u.getDefaultService(), hosts, matchers);
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
import java.util.List;

public class ServicioDeRutas {

    private final UrlMapsGcp urlMaps;
    private final SimuladorDeUrlMap simulador = new SimuladorDeUrlMap();

    public ServicioDeRutas(UrlMapsGcp urlMaps) {
        this.urlMaps = urlMaps;
    }

    /** Pruebas de enrutamiento para el pipeline: fallan si una ruta crítica cambia de destino. */
    public List<SimuladorDeUrlMap.ResultadoPrueba> probar(String urlMap, List<SimuladorDeUrlMap.Prueba> pruebas) {
        return simulador.probar(urlMaps.leer(urlMap), pruebas);
    }
}
'''
ggen.gcp('gcp/05-ingress-api/cloud-load-balancing', 'Ingress y API · Cloud Load Balancing',
  'Un **simulador del URL map** para pruebas de enrutamiento en el pipeline: lee el URL map real con `UrlMapsClient.get`, lo convierte a un modelo simple (reglas de host, path matchers, reglas de ruta) y resuelve host + ruta al servicio de backend (exacta antes que prefijo, prefijo más largo gana). Complementa a `gcloud compute url-maps validate` y a los `test` del propio URL map.',
  [],
  [('Simulador (lógica pura)', SIM, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Rutas', '/ingress/rutas', 'ServicioDeRutas', 'UrlMapsGcp', ['import java.util.List;'],
  'return new UrlMapsGcp(cred, proyecto);',
  [dict(n='probar', v='POST', p='/{urlMap}/pruebas', args=[('String', 'urlMap', 'p'), ('List<SimuladorDeUrlMap.Prueba>', 'pruebas', 'b')], ret='List<SimuladorDeUrlMap.ResultadoPrueba>', call='s.probar(urlMap, pruebas)')],
  [('Leer URL maps', '`roles/compute.loadBalancerAdmin` o `roles/compute.viewer`')],
  ['No reemplaces la validación oficial: el simulador no cubre `routeRules` avanzadas (cabeceras, pesos).',
   'No modifiques el URL map desde la app.',
   'No olvides probar el host por defecto y rutas sin barra final.'])
