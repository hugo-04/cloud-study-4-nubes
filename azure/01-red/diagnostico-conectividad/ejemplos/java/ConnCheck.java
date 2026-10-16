import java.net.ConnectException;
import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import java.net.SocketTimeoutException;

/**
 * Prueba de conectividad en dos pasos: DNS y TCP.
 * Sirve para saber DONDE falla algo (DNS, ruta/firewall o puerto cerrado).
 *
 * Uso (Java 11+):
 *   java ConnCheck.java <host> <puerto> [timeoutMs]
 *
 * Ejemplo dentro de un pod:
 *   kubectl run jdk --rm -it --image=eclipse-temurin:21 -- bash
 *   (pega este archivo y ejecutalo)
 *
 * Nota: el texto de salida no usa acentos a proposito, para que se vea bien
 * en cualquier consola o contenedor, aunque no tenga UTF-8.
 */
public class ConnCheck {

    public static void main(String[] args) {
        if (args.length < 2) {
            System.out.println("Uso: java ConnCheck.java <host> <puerto> [timeoutMs]");
            return;
        }

        String host = args[0];
        int port = Integer.parseInt(args[1]);
        int timeoutMs = args.length > 2 ? Integer.parseInt(args[2]) : 3000;

        // Paso 1: DNS
        System.out.println("1) DNS: resolviendo " + host);
        InetAddress[] ips;
        try {
            ips = InetAddress.getAllByName(host);
        } catch (Exception e) {
            System.out.println("   FALLO DNS -> el nombre no resuelve");
            System.out.println("   Revisa: zona privada sin enlace a la VNet, DNS personalizado sin reenvio, nombre mal escrito");
            System.out.println("   Detalle: " + e.getMessage());
            return;
        }
        for (InetAddress ip : ips) {
            System.out.println("   -> " + ip.getHostAddress() + "  " + clasificar(ip));
        }

        // Paso 2: TCP
        System.out.println("2) TCP: conectando a " + host + ":" + port + " (timeout " + timeoutMs + " ms)");
        long inicio = System.currentTimeMillis();
        try (Socket socket = new Socket()) {
            socket.connect(new InetSocketAddress(ips[0], port), timeoutMs);
            System.out.println("   OK en " + (System.currentTimeMillis() - inicio) + " ms -> red y puerto bien");
            System.out.println("   Si aun asi falla la app: mira TLS (certificado) o identidad (401/403).");
        } catch (SocketTimeoutException e) {
            System.out.println("   TIMEOUT -> los paquetes se descartan: revisa NSG/firewall, rutas (UDR) y peering");
        } catch (ConnectException e) {
            System.out.println("   RECHAZADO o sin ruta -> llego al destino pero nadie escucha en ese puerto, o hay un REJECT");
            System.out.println("   Detalle: " + e.getMessage());
        } catch (Exception e) {
            System.out.println("   ERROR inesperado: " + e);
        }
    }

    private static String clasificar(InetAddress ip) {
        if (ip.isLoopbackAddress()) {
            return "LOOPBACK (esta misma maquina)";
        }
        if (ip.isLinkLocalAddress()) {
            return "LINK-LOCAL (169.254.x.x / fe80::)";
        }
        if (ip.isSiteLocalAddress()) {
            return "PRIVADA";
        }
        return "PUBLICA (si esperabas privada, revisa Private Endpoint y la zona DNS)";
    }
}
