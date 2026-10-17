import java.net.InetAddress;
import java.net.InetSocketAddress;
import java.net.Socket;
import javax.net.ssl.SSLSocket;
import javax.net.ssl.SSLSocketFactory;

/**
 * Herramienta de diagnóstico: DNS -> TCP -> (opcional) TLS.
 * Uso: java ConnCheck.java <host> <puerto> [--tls]
 */
public class ConnCheck {
    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("uso: java ConnCheck.java <host> <puerto> [--tls]");
            System.exit(2);
        }
        String host = args[0];
        int puerto = Integer.parseInt(args[1]);
        boolean tls = args.length > 2 && args[2].equals("--tls");

        System.out.println("== 1. DNS ==");
        InetAddress[] dirs;
        try {
            dirs = InetAddress.getAllByName(host);
        } catch (java.net.UnknownHostException e) {
            System.out.println("FALLA: el nombre no resuelve (DNS privado, zona privada o nombre mal escrito)");
            System.exit(1);
            return;
        }
        for (InetAddress d : dirs) {
            System.out.println("  " + d.getHostAddress() + (d.isSiteLocalAddress() ? "  (privada)" : d.isLoopbackAddress() ? "  (loopback)" : "  (PÚBLICA)"));
        }

        System.out.println("== 2. TCP ==");
        long t0 = System.nanoTime();
        try (Socket s = new Socket()) {
            s.connect(new InetSocketAddress(dirs[0], puerto), 3000);
            System.out.printf("OK conectó en %d ms%n", (System.nanoTime() - t0) / 1_000_000);
            if (tls) {
                System.out.println("== 3. TLS ==");
                try (SSLSocket ssl = (SSLSocket) ((SSLSocketFactory) SSLSocketFactory.getDefault()).createSocket(s, host, puerto, false)) {
                    ssl.startHandshake();
                    System.out.println("OK " + ssl.getSession().getProtocol() + " " + ssl.getSession().getPeerPrincipal());
                }
            }
        } catch (java.net.SocketTimeoutException e) {
            System.out.println("TIMEOUT: algo descarta el tráfico (SG, NACL, ruta). Siguiente: Reachability Analyzer y Flow Logs");
            System.exit(1);
        } catch (java.net.ConnectException e) {
            System.out.println("REFUSED: el tráfico llegó pero nadie escucha en ese puerto (" + e.getMessage() + ")");
            System.exit(1);
        } catch (javax.net.ssl.SSLException e) {
            System.out.println("TLS FALLA: " + e.getMessage() + " (certificado, nombre o SNI)");
            System.exit(1);
        }
    }
}
