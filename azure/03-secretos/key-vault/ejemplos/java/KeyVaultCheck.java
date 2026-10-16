import com.azure.core.exception.HttpResponseException;
import com.azure.core.exception.ResourceNotFoundException;
import com.azure.identity.CredentialUnavailableException;
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.security.keyvault.secrets.SecretClient;
import com.azure.security.keyvault.secrets.SecretClientBuilder;
import com.azure.security.keyvault.secrets.models.KeyVaultSecret;
import java.net.InetAddress;
import java.net.URI;
import java.time.Duration;
import java.time.Instant;

/**
 * Diagnóstico de acceso a Key Vault, pensado para ejecutarse DENTRO del entorno que falla
 * (pod, App Service por SSH, VM). Imprime en qué capa se rompe: DNS, token o permiso.
 * Nunca imprime el valor del secreto.
 *
 * Uso: java KeyVaultCheck.java https://kv-modalima-estudio01.vault.azure.net db-password
 */
public class KeyVaultCheck {

    public static void main(String[] args) throws Exception {
        if (args.length < 2) {
            System.err.println("Uso: KeyVaultCheck <vaultUrl> <nombreSecreto>");
            System.exit(2);
        }
        String url = args[0];
        String nombre = args[1];
        String host = URI.create(url).getHost();

        // 1) DNS: ¿a qué IP resuelve? Una IP privada indica que el Private Endpoint y la zona DNS funcionan.
        try {
            for (InetAddress a : InetAddress.getAllByName(host)) {
                System.out.println("DNS    " + host + " -> " + a.getHostAddress()
                        + (a.isSiteLocalAddress() ? "  (privada)" : "  (pública)"));
            }
        } catch (Exception e) {
            System.out.println("DNS    FALLA: " + e);
            System.exit(1);
        }

        // 2) Token y 3) lectura
        SecretClient cliente = new SecretClientBuilder()
                .vaultUrl(url)
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient();

        Instant inicio = Instant.now();
        try {
            KeyVaultSecret s = cliente.getSecret(nombre);
            System.out.println("OK     secreto '" + nombre + "' leído en "
                    + Duration.between(inicio, Instant.now()).toMillis() + " ms");
            System.out.println("       versión: " + s.getProperties().getVersion());
            System.out.println("       activo:  " + s.getProperties().isEnabled());
            System.out.println("       vence:   " + s.getProperties().getExpiresOn());
        } catch (CredentialUnavailableException e) {
            System.out.println("TOKEN  sin credencial disponible: falta identidad asignada, "
                    + "variables de workload identity o `az login`.");
            System.exit(1);
        } catch (ResourceNotFoundException e) {
            System.out.println("404    el secreto no existe, está deshabilitado o el vault es otro.");
            System.exit(1);
        } catch (HttpResponseException e) {
            int estado = e.getResponse().getStatusCode();
            System.out.println("HTTP   " + estado + " -> " + interpretar(estado));
            System.out.println("       " + e.getMessage().lines().findFirst().orElse(""));
            System.exit(1);
        }
    }

    private static String interpretar(int estado) {
        return switch (estado) {
            case 401 -> "token inválido o audiencia/tenant equivocados";
            case 403 -> "falta rol de datos (Key Vault Secrets User) o la red de origen no está permitida (firewall/PE/DNS)";
            case 429 -> "demasiadas peticiones: cachea el secreto";
            default -> "revisa el mensaje completo";
        };
    }
}
