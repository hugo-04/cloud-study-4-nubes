import sys, os; sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import jdoc
LLAVES = '''
/** Lo que necesita el sobre de Vault: una llave de datos nueva y poder abrir una envuelta. */
public interface Llaves {

    /** Llave de datos: en claro (para usar y olvidar) y envuelta (para guardar). */
    record LlaveDeDatos(byte[] enClaro, String envuelta) { }

    LlaveDeDatos nueva();

    byte[] abrir(String envuelta);
}
'''
SOBRE = '''
import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import java.util.Arrays;
import java.util.Base64;
import javax.crypto.Cipher;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/** Cifrado de sobre: AES-256-GCM local con una llave de datos protegida por Vault. */
public class CifradoDeSobre {

    private static final String VERSION = "v1";
    private static final int IV_BYTES = 12;
    private static final int TAG_BITS = 128;

    private final Llaves llaves;
    private final SecureRandom azar = new SecureRandom();

    public CifradoDeSobre(Llaves llaves) {
        this.llaves = llaves;
    }

    /** Formato: v1.llaveEnvuelta.iv.textoCifrado (todo en Base64 URL). */
    public String cifrar(String texto, String contexto) {
        var dek = llaves.nueva();
        try {
            byte[] iv = new byte[IV_BYTES];
            azar.nextBytes(iv);
            byte[] cifrado = aes(Cipher.ENCRYPT_MODE, dek.enClaro(), iv, contexto, texto.getBytes(StandardCharsets.UTF_8));
            var b64 = Base64.getUrlEncoder().withoutPadding();
            return String.join(".", VERSION, b64.encodeToString(dek.envuelta().getBytes(StandardCharsets.UTF_8)),
                b64.encodeToString(iv), b64.encodeToString(cifrado));
        } finally {
            Arrays.fill(dek.enClaro(), (byte) 0);
        }
    }

    public String descifrar(String sobre, String contexto) {
        String[] p = sobre.split("\\\\.");
        if (p.length != 4 || !VERSION.equals(p[0])) {
            throw new IllegalArgumentException("formato de sobre desconocido");
        }
        var b64 = Base64.getUrlDecoder();
        String envuelta = new String(b64.decode(p[1]), StandardCharsets.UTF_8);
        byte[] clave = llaves.abrir(envuelta);
        try {
            return new String(aes(Cipher.DECRYPT_MODE, clave, b64.decode(p[2]), contexto, b64.decode(p[3])), StandardCharsets.UTF_8);
        } finally {
            Arrays.fill(clave, (byte) 0);
        }
    }

    private static byte[] aes(int modo, byte[] clave, byte[] iv, String contexto, byte[] datos) {
        try {
            var c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(modo, new SecretKeySpec(clave, "AES"), new GCMParameterSpec(TAG_BITS, iv));
            c.updateAAD(contexto.getBytes(StandardCharsets.UTF_8));
            return c.doFinal(datos);
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("no se pudo cifrar/descifrar (¿contexto distinto o dato alterado?)", e);
        }
    }
}
'''
SDK = '''
import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;
import com.oracle.bmc.keymanagement.KmsCryptoClient;
import com.oracle.bmc.keymanagement.model.DecryptDataDetails;
import com.oracle.bmc.keymanagement.model.GenerateKeyDetails;
import com.oracle.bmc.keymanagement.model.KeyShape;
import com.oracle.bmc.keymanagement.requests.DecryptRequest;
import com.oracle.bmc.keymanagement.requests.GenerateDataEncryptionKeyRequest;
import java.util.Base64;

/** Implementa Llaves con el endpoint de criptografía del vault. */
public class LlavesKms implements Llaves, AutoCloseable {

    private final KmsCryptoClient cliente;
    private final String llaveMaestraId;

    public LlavesKms(BasicAuthenticationDetailsProvider auth, String endpointCripto, String llaveMaestraId) {
        this.cliente = KmsCryptoClient.builder().endpoint(endpointCripto).build(auth);
        this.llaveMaestraId = llaveMaestraId;
    }

    @Override
    public LlaveDeDatos nueva() {
        var detalles = GenerateKeyDetails.builder()
            .keyId(llaveMaestraId)
            .includePlaintextKey(true)
            .keyShape(KeyShape.builder().algorithm(KeyShape.Algorithm.Aes).length(32).build())
            .build();
        var k = cliente.generateDataEncryptionKey(
            GenerateDataEncryptionKeyRequest.builder().generateKeyDetails(detalles).build()).getGeneratedKey();
        return new LlaveDeDatos(Base64.getDecoder().decode(k.getPlaintext()), k.getCiphertext());
    }

    @Override
    public byte[] abrir(String envuelta) {
        var detalles = DecryptDataDetails.builder().keyId(llaveMaestraId).ciphertext(envuelta).build();
        var r = cliente.decrypt(DecryptRequest.builder().decryptDataDetails(detalles).build()).getDecryptedData();
        return Base64.getDecoder().decode(r.getPlaintext());
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SERV = '''
public class ServicioDeCifrado {

    private final CifradoDeSobre sobre;

    public ServicioDeCifrado(CifradoDeSobre sobre) {
        this.sobre = sobre;
    }

    public record Peticion(String id, String texto) { }

    public record Sobre(String id, String valor) { }

    public Sobre cifrar(Peticion p) {
        return new Sobre(p.id(), sobre.cifrar(p.texto(), p.id()));
    }

    /** El id es el contexto autenticado: un sobre copiado a otro id no se abre. */
    public String descifrar(String id, String valor) {
        return sobre.descifrar(valor, id);
    }
}
'''
sec = dict(
  ns='Cifrado', ruta='/secretos/cifrado', servicio='ServicioDeCifrado',
  spring_imports=['import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;', 'import org.springframework.beans.factory.annotation.Value;'],
  spring_beans='''    @Bean(destroyMethod = "close")
    LlavesKms llavesKms(@Value("${oci.auth}") String modo, @Value("${kms.endpoint-cripto}") String endpoint,
                        @Value("${kms.llave-id}") String llaveId) {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(modo);
        return new LlavesKms(auth, endpoint, llaveId);
    }

    @Bean
    ServicioDeCifrado servicioDeCifrado(LlavesKms llaves) {
        return new ServicioDeCifrado(new CifradoDeSobre(llaves));
    }
''',
  q_imports=['import com.oracle.bmc.auth.BasicAuthenticationDetailsProvider;', 'import jakarta.enterprise.inject.Disposes;'],
  q_fields=[('String', 'modo', 'oci.auth'), ('String', 'endpoint', 'kms.endpoint-cripto'), ('String', 'llaveId', 'kms.llave-id')],
  q_producer='''    LlavesKms llavesKms() {
        BasicAuthenticationDetailsProvider auth = Autenticacion.crear(modo);
        return new LlavesKms(auth, endpoint, llaveId);
    }

    void cerrar(@Disposes LlavesKms l) {
        l.close();
    }

    @jakarta.enterprise.inject.Produces
    @Singleton
    ServicioDeCifrado servicioDeCifrado(LlavesKms llaves) {
        return new ServicioDeCifrado(new CifradoDeSobre(llaves));
    }''',
  endpoints=[
    dict(n='cifrar', v='POST', p='/cifrar', args=[('ServicioDeCifrado.Peticion', 'p', 'b')], ret='ServicioDeCifrado.Sobre', call='s.cifrar(p)'),
    dict(n='descifrar', v='GET', p='/descifrar', args=[('String', 'id', 'q'), ('String', 'valor', 'q')], ret='String', call='s.descifrar(id, valor)'),
  ])
jdoc.doc(os.path.join(os.path.dirname(os.path.abspath(__file__)), '../oci/03-secretos/vault-kms/uso-en-java.md'),
  'Secretos · Vault: llaves (KMS)',
  'Un **cifrado de sobre**: el núcleo (AES-256-GCM con contexto autenticado) es Java puro y se prueba sin red; solo la obtención y apertura de la llave de datos usa `KmsCryptoClient` con el endpoint de criptografía del vault.',
  'oci:\n  auth: instance\nkms:\n  endpoint-cripto: https://xxxx-crypto.kms.sa-saopaulo-1.oraclecloud.com\n  llave-id: ocid1.key.oc1.sa-saopaulo-1.xxxx',
  'oci.auth=instance\nkms.endpoint-cripto=https://xxxx-crypto.kms.sa-saopaulo-1.oraclecloud.com\nkms.llave-id=ocid1.key.oc1.sa-saopaulo-1.xxxx',
  [('Contrato con el Vault', LLAVES, True), ('Cifrado de sobre', SOBRE, True), ('Implementación con el SDK', SDK, True), ('Servicio', SERV, True)],
  sec,
  [('`GenerateDataEncryptionKey`, `Decrypt`', '`Allow dynamic-group app-tienda-prod to use keys in compartment tienda-prod where target.key.id = \'<ocid>\'`')],
  ['No registres la llave de datos en claro, ni el texto descifrado; el código borra el arreglo de bytes tras usarlo.',
   'No reutilices un IV con la misma llave (el código genera uno aleatorio por mensaje y una DEK nueva cada vez).',
   'No expongas `/descifrar` sin autenticación y autorización propias: devuelve el dato en claro.',
   'No uses `Encrypt` directo para datos grandes.',
   'No ejecutes el SDK síncrono en el bucle de eventos (WebFlux/Vert.x).'])
