# Azure · Workload Identity · Uso desde Java

Buena noticia: **tu código no cambia**. El mismo `DefaultAzureCredential` reconoce las variables que inyecta el webhook y hace el intercambio de tokens.

## 1. Código
```java
import com.azure.identity.DefaultAzureCredentialBuilder;
import com.azure.security.keyvault.secrets.SecretClient;
import com.azure.security.keyvault.secrets.SecretClientBuilder;

class SecretosConfig {
    static SecretClient cliente() {
        return new SecretClientBuilder()
                .vaultUrl("https://kv-modalima-prod.vault.azure.net")
                .credential(new DefaultAzureCredentialBuilder().build())
                .buildClient();
    }

    static String leer(String nombre) {
        return cliente().getSecret(nombre).getValue();
    }
}
```
Dependencias: `com.azure:azure-security-keyvault-secrets` y `com.azure:azure-identity`.

## 2. Forzar la credencial de workload identity (más predecible en producción)
```java
import com.azure.identity.WorkloadIdentityCredential;
import com.azure.identity.WorkloadIdentityCredentialBuilder;

WorkloadIdentityCredential credencial = new WorkloadIdentityCredentialBuilder().build();
// Usa AZURE_CLIENT_ID, AZURE_TENANT_ID y AZURE_FEDERATED_TOKEN_FILE del entorno.
```

## 3. Spring Boot
```properties
# La credencial se resuelve con DefaultAzureCredential; no pongas secretos.
spring.cloud.azure.keyvault.secret.property-sources[0].endpoint=https://kv-modalima-prod.vault.azure.net
spring.cloud.azure.credential.managed-identity-enabled=false
```
> Con workload identity no se usa el IMDS del nodo. Deja `managed-identity-enabled=false` y deja que `DefaultAzureCredential` use el token federado. Verifica en la documentación de Spring Cloud Azure el flag recomendado en tu versión.

## 4. Quarkus
```properties
quarkus.azure.keyvault.secret.endpoint=https://kv-modalima-prod.vault.azure.net
```
(Las extensiones de Quarkiverse usan `DefaultAzureCredential`.)

## 5. Lo que debes pedir en el Deployment
Ver [`ejemplos/yaml/deployment.yaml`](ejemplos/yaml/deployment.yaml):
- `serviceAccountName: sa-api`
- Etiqueta del **pod**: `azure.workload.identity/use: "true"`

## 6. Diagnóstico desde dentro del pod
```bash
env | grep -E "AZURE_(CLIENT_ID|TENANT_ID|FEDERATED_TOKEN_FILE|AUTHORITY_HOST)"
ls -l "$AZURE_FEDERATED_TOKEN_FILE"
# Ver solo los claims relevantes del token proyectado (no lo muestres completo):
cut -d. -f2 "$AZURE_FEDERATED_TOKEN_FILE" | base64 -d 2>/dev/null | python3 -c "import json,sys; d=json.load(sys.stdin); print({k:d[k] for k in ('iss','sub','aud')})"
```
El `sub` debe coincidir **exactamente** con el subject de la credencial federada.

## 7. Errores típicos en logs
| Mensaje | Causa |
|---|---|
| `AADSTS70021: No matching federated identity record found` | `issuer`/`subject`/`audience` no coinciden |
| `AADSTS700211: No matching federated identity record found for presented assertion issuer` | El issuer de la credencial federada no es el del clúster |
| `CredentialUnavailableException` | El pod no recibió las variables: falta etiqueta, ServiceAccount o webhook |
| 403 del servicio | Faltan roles para la identidad |
