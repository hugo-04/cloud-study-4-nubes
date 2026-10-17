import ggen
SOBRE = '''
import java.nio.ByteBuffer;
import java.security.GeneralSecurityException;
import java.security.SecureRandom;
import javax.crypto.Cipher;
import javax.crypto.KeyGenerator;
import javax.crypto.SecretKey;
import javax.crypto.spec.GCMParameterSpec;
import javax.crypto.spec.SecretKeySpec;

/** Cifrado de sobre: AES-256-GCM local con DEK y AAD; la DEK la envuelve KMS. Puro (sin red). */
public class CifradoDeSobre {

    public record Sobre(byte[] dekEnvuelta, byte[] nonce, byte[] cifrado) { }

    public interface Envolvedor {
        byte[] envolver(byte[] dek, byte[] aad);

        byte[] desenvolver(byte[] dekEnvuelta, byte[] aad);
    }

    private static final SecureRandom AZAR = new SecureRandom();
    private final Envolvedor kms;

    public CifradoDeSobre(Envolvedor kms) {
        this.kms = kms;
    }

    public Sobre cifrar(byte[] datos, byte[] aad) {
        try {
            KeyGenerator kg = KeyGenerator.getInstance("AES");
            kg.init(256);
            SecretKey dek = kg.generateKey();
            byte[] nonce = new byte[12];
            AZAR.nextBytes(nonce);
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.ENCRYPT_MODE, dek, new GCMParameterSpec(128, nonce));
            c.updateAAD(aad);
            byte[] cifrado = c.doFinal(datos);
            return new Sobre(kms.envolver(dek.getEncoded(), aad), nonce, cifrado);
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException(e);
        }
    }

    public byte[] descifrar(Sobre s, byte[] aad) {
        try {
            byte[] dek = kms.desenvolver(s.dekEnvuelta(), aad);
            Cipher c = Cipher.getInstance("AES/GCM/NoPadding");
            c.init(Cipher.DECRYPT_MODE, new SecretKeySpec(dek, "AES"), new GCMParameterSpec(128, s.nonce()));
            c.updateAAD(aad);
            return c.doFinal(s.cifrado());
        } catch (GeneralSecurityException e) {
            throw new IllegalStateException("no se pudo descifrar: contexto (AAD) o datos alterados", e);
        }
    }

    /** Formato de almacenamiento: [len dek][dek][nonce 12][cifrado]. */
    public static byte[] serializar(Sobre s) {
        return ByteBuffer.allocate(4 + s.dekEnvuelta().length + 12 + s.cifrado().length)
            .putInt(s.dekEnvuelta().length).put(s.dekEnvuelta()).put(s.nonce()).put(s.cifrado()).array();
    }

    public static Sobre deserializar(byte[] b) {
        var buf = ByteBuffer.wrap(b);
        byte[] dek = new byte[buf.getInt()];
        buf.get(dek);
        byte[] nonce = new byte[12];
        buf.get(nonce);
        byte[] cif = new byte[buf.remaining()];
        buf.get(cif);
        return new Sobre(dek, nonce, cif);
    }
}
'''
SDK = '''
import com.google.api.gax.core.FixedCredentialsProvider;
import com.google.auth.oauth2.GoogleCredentials;
import com.google.cloud.kms.v1.CryptoKeyName;
import com.google.cloud.kms.v1.DecryptRequest;
import com.google.cloud.kms.v1.EncryptRequest;
import com.google.cloud.kms.v1.KeyManagementServiceClient;
import com.google.cloud.kms.v1.KeyManagementServiceSettings;
import com.google.protobuf.ByteString;
import java.io.IOException;
import java.io.UncheckedIOException;

/** Adaptador: KMS envuelve y desenvuelve la DEK con la misma AAD. */
public class KmsGcp implements CifradoDeSobre.Envolvedor, AutoCloseable {

    private final KeyManagementServiceClient cliente;
    private final String llave;

    public KmsGcp(GoogleCredentials cred, String proyecto, String ubicacion, String llavero, String nombreLlave) {
        try {
            this.cliente = KeyManagementServiceClient.create(KeyManagementServiceSettings.newBuilder()
                .setCredentialsProvider(FixedCredentialsProvider.create(cred)).build());
        } catch (IOException e) {
            throw new UncheckedIOException(e);
        }
        this.llave = CryptoKeyName.of(proyecto, ubicacion, llavero, nombreLlave).toString();
    }

    @Override
    public byte[] envolver(byte[] dek, byte[] aad) {
        return cliente.encrypt(EncryptRequest.builder().setName(llave).setPlaintext(ByteString.copyFrom(dek))
            .setAdditionalAuthenticatedData(ByteString.copyFrom(aad)).build()).getCiphertext().toByteArray();
    }

    @Override
    public byte[] desenvolver(byte[] dekEnvuelta, byte[] aad) {
        return cliente.decrypt(DecryptRequest.newBuilder().setName(llave).setCiphertext(ByteString.copyFrom(dekEnvuelta))
            .setAdditionalAuthenticatedData(ByteString.copyFrom(aad)).build()).getPlaintext().toByteArray();
    }

    @Override
    public void close() {
        cliente.close();
    }
}
'''
SDK = SDK.replace("EncryptRequest.builder()", "EncryptRequest.newBuilder()")
SERV = '''
import java.nio.charset.StandardCharsets;
import java.util.Base64;

public class ServicioDeCifrado {

    private final CifradoDeSobre sobre;

    public ServicioDeCifrado(KmsGcp kms) {
        this.sobre = new CifradoDeSobre(kms);
    }

    /** El id del cliente es el contexto: un documento copiado a otro cliente no se descifra. */
    public String cifrar(String idCliente, String documento) {
        var s = sobre.cifrar(documento.getBytes(StandardCharsets.UTF_8), ("cliente:" + idCliente).getBytes(StandardCharsets.UTF_8));
        return Base64.getEncoder().encodeToString(CifradoDeSobre.serializar(s));
    }

    public String descifrar(String idCliente, String base64) {
        var s = CifradoDeSobre.deserializar(Base64.getDecoder().decode(base64));
        return new String(sobre.descifrar(s, ("cliente:" + idCliente).getBytes(StandardCharsets.UTF_8)), StandardCharsets.UTF_8);
    }
}
'''
ggen.gcp('gcp/03-secretos/cloud-kms', 'Secretos · Cloud KMS',
  '**Cifrado de sobre con contexto**: la lógica pura genera una DEK AES-256 por documento, cifra con AES-GCM usando como AAD el id del cliente y delega a KMS envolver/desenvolver la DEK (con la misma AAD) mediante `KeyManagementServiceClient.encrypt/decrypt`. Un documento copiado al registro de otro cliente no se descifra.',
  [('kms.ubicacion', 'southamerica-west1'), ('kms.llavero', 'tienda'), ('kms.llave', 'datos-clientes')],
  [('Cifrado de sobre (lógica pura)', SOBRE, True), ('Adaptador de la biblioteca', SDK, True), ('Servicio', SERV, True)],
  'Cifrado', '/secretos/cifrado', 'ServicioDeCifrado', 'KmsGcp', [],
  'return new KmsGcp(cred, proyecto, ubicacion, llavero, llave);',
  [dict(n='cifrar', v='POST', p='/{cliente}/cifrar', args=[('String', 'cliente', 'p'), ('String', 'doc', 'b')], ret='String', call='s.cifrar(cliente, doc)'),
   dict(n='descifrar', v='POST', p='/{cliente}/descifrar', args=[('String', 'cliente', 'p'), ('String', 'b64', 'b')], ret='String', call='s.descifrar(cliente, b64)')],
  [('Envolver y desenvolver DEK', '`roles/cloudkms.cryptoKeyEncrypterDecrypter` **en esa llave**')],
  ['No envíes documentos grandes a `encrypt`: cifra localmente y envuelve la DEK.',
   'No reutilices nonce con la misma DEK.',
   'No omitas la AAD.',
   'No registres DEK ni texto plano.',
   'No uses el endpoint de descifrado sin autorización de negocio (¿este usuario puede ver este documento?).'])
