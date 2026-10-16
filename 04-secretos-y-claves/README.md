# 04 · Secretos, claves y certificados (Key Vault y equivalentes)

**Azure Key Vault** guarda y protege secretos, claves de cifrado y certificados. Equivalentes: **AWS Secrets Manager + KMS**, **OCI Vault** y **GCP Secret Manager + Cloud KMS**.

---

## 1. Qué es (con analogía)

Una **caja fuerte de banco con registro de visitas**. Las aplicaciones no llevan la contraseña de la base de datos en el bolsillo (el código): la piden a la caja fuerte cada vez, con su gafete (identidad), y queda anotado quién la pidió y cuándo.

| Objeto | Qué es | Analogía |
|---|---|---|
| **Secreto** | Texto que debe permanecer privado: contraseña, token, connection string | La combinación de una caja |
| **Clave (key)** | Material criptográfico para cifrar, firmar | El molde de una llave que **nunca sale** de la caja fuerte |
| **Certificado** | Certificado TLS/X.509 con su ciclo de vida | El carné con vigencia |

> Diferencia clave: un **secreto** se lee y se usa fuera; una **clave** normalmente **no se extrae**: le pides al servicio que cifre o firme por ti.

---

## 2. Para qué sirve y cuándo NO usarlo

**Sirve para**
- Quitar contraseñas del código y de los repositorios.
- Rotar credenciales sin redesplegar.
- Cifrar datos con claves que tú controlas (CMK).
- Guardar certificados y renovarlos.
- Auditar quién accedió a qué.

**Cuándo NO usarlo**
- **Configuración no sensible** (nombres, URLs, flags): usa App Configuration / ConfigMaps / Parameter Store.
- **Datos grandes** (archivos, blobs): un vault no es una base de datos; guarda los datos en Storage y la **clave** en el vault.
- **Millones de lecturas por segundo**: los vaults tienen límites de peticiones; guarda el secreto en memoria con una caché corta.

---

## 3. Conceptos clave

| Término | Definición simple |
|---|---|
| **Vault** | El contenedor (un Key Vault, un Vault de OCI) |
| **Versión** | Cada cambio de un secreto crea una versión; la app suele pedir "la última" |
| **Soft delete** | Lo borrado queda recuperable un tiempo |
| **Purge protection** | Impide borrar definitivamente antes de que pase ese tiempo |
| **Cifrado de sobre (envelope)** | Una **clave de datos** cifra tus datos; la **clave maestra** (en el vault) cifra la clave de datos |
| **CMK** | Customer-Managed Key: tú controlas la clave con la que el servicio cifra tus datos |
| **HSM** | Módulo de hardware dedicado; la clave nunca sale del hardware |
| **Rotación** | Cambiar el secreto o clave periódicamente |

---

## 4. Equivalencias en las 4 nubes

| Concepto | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| Secretos | Key Vault (secrets) | **Secrets Manager** (y SSM Parameter Store para config) | **Vault** (secrets) | **Secret Manager** |
| Claves de cifrado | Key Vault (keys) / Managed HSM | **KMS** (y CloudHSM) | Vault (master encryption keys) | **Cloud KMS** (y Cloud HSM) |
| Certificados | Key Vault (certificates) | **ACM** (Certificate Manager) | **Certificates service** | **Certificate Manager** |
| Modelo de acceso | Azure RBAC (recomendado) o access policies | IAM + *key policy* de KMS | Políticas por compartimento | IAM sobre el secreto/clave |
| Rotación automática | Eventos + Function / rotación en algunos secretos | Rotación nativa con Lambda | Rotación configurable | Programa de rotación + Pub/Sub |
| Acceso privado | Private Endpoint | Interface VPC Endpoint | Private Endpoint del Vault | Private Service Connect |
| Recuperación de borrados | Soft delete + purge protection | Ventana de recuperación (7–30 días) | Programar borrado (mínimo varios días) | Versiones destruibles con retraso |
| Inyección a pods | CSI Secrets Store + Workload Identity | External Secrets / CSI + IRSA | External Secrets (OCI Vault) | Secret Manager CSI / External Secrets |

### Diferencias reales

- En **AWS** secretos y claves están **separados**: Secrets Manager para contraseñas, KMS para cifrado. En **Azure** viven en el mismo servicio (Key Vault).
- **Secrets Manager** tiene **rotación nativa** (con una función Lambda); en Azure normalmente armas la rotación con eventos y una Function.
- **KMS** de AWS tiene *key policy* **además** de IAM: ambas deben permitir.
- En **OCI** las claves se protegen por software o por HSM según el tipo de vault.
- **GCP** puede versionar secretos de forma nativa con alias (`latest`).

---

## 5. Key Vault en detalle (Azure)

### 5.1 Modelo de permisos: RBAC vs access policies

| | Azure RBAC (**recomendado**) | Access policies (clásico) |
|---|---|---|
| Granularidad | Por vault, por secreto, por clave | Por vault |
| Gestión | Igual que el resto de Azure | Política propia del vault |
| Auditoría y PIM | Sí | Limitado |

Roles útiles:

| Rol | Para quién |
|---|---|
| Key Vault Secrets User | **Aplicaciones** que leen secretos |
| Key Vault Secrets Officer | Quien administra secretos |
| Key Vault Crypto User | Apps que cifran/firman con una clave |
| Key Vault Certificates Officer | Quien administra certificados |
| Key Vault Administrator | Control total de datos (uso restringido) |
| Key Vault Contributor | Administra el **vault**, **no** sus datos |

> Igual que en el módulo 03: **Contributor** sobre el vault no te deja leer secretos.

### 5.2 Crear un vault seguro (CLI)

```bash
RG=rg-estudio-sec
KV=kv-modalima-estudio01     # único global

az group create -n $RG -l eastus2

az keyvault create -g $RG -n $KV \
  --enable-rbac-authorization true \
  --retention-days 30 \
  --enable-purge-protection true \
  --public-network-access Disabled

# Dar permiso para administrar secretos a quien opera
az role assignment create --assignee <TU_USUARIO_O_GRUPO_ID> \
  --role "Key Vault Secrets Officer" \
  --scope $(az keyvault show -g $RG -n $KV --query id -o tsv)

# Guardar un secreto
az keyvault secret set --vault-name $KV -n db-password --value '<valor>' --expires 2027-04-01T00:00:00Z

# Dar lectura a la identidad de la aplicación
az role assignment create --assignee-object-id <PRINCIPAL_ID_APP> \
  --assignee-principal-type ServicePrincipal \
  --role "Key Vault Secrets User" \
  --scope $(az keyvault show -g $RG -n $KV --query id -o tsv)
```

> Con `public-network-access Disabled`, desde tu laptop **no podrás** crear secretos hasta tener Private Endpoint y acceso a la red (módulos 01 y 02). Para el lab puedes dejarlo en `Enabled` con reglas de firewall limitadas a tu IP, y luego cerrarlo.

Private Endpoint (resumen; el paso a paso está en el módulo 02): grupo `vault` y zona `privatelink.vaultcore.azure.net`.

### 5.3 Terraform (Azure)

```hcl
data "azurerm_client_config" "actual" {}

resource "azurerm_key_vault" "kv" {
  name                       = "kv-modalima-estudio01"
  location                   = azurerm_resource_group.rg.location
  resource_group_name        = azurerm_resource_group.rg.name
  tenant_id                  = data.azurerm_client_config.actual.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true   # en versiones antiguas del provider: enable_rbac_authorization
  purge_protection_enabled   = true
  soft_delete_retention_days = 30
  public_network_access_enabled = false
}
```
> Los nombres de atributos cambian entre versiones del provider `azurerm`. Confirma con `terraform validate`.

### 5.4 Cómo la aplicación lee el secreto

**Opción A: desde el código (Java)**
```java
SecretClient cliente = new SecretClientBuilder()
    .vaultUrl("https://kv-modalima-estudio01.vault.azure.net")
    .credential(new DefaultAzureCredentialBuilder().build())
    .buildClient();

String password = cliente.getSecret("db-password").getValue();
```

**Opción B: referencia desde App Service / Functions (sin tocar el código)**
```
DB_PASSWORD = @Microsoft.KeyVault(SecretUri=https://kv-modalima-estudio01.vault.azure.net/secrets/db-password/)
```
La plataforma resuelve el valor usando la identidad administrada de la app.

**Opción C: AKS con el CSI Secrets Store**
```yaml
apiVersion: secrets-store.csi.x-k8s.io/v1
kind: SecretProviderClass
metadata:
  name: kv-api
  namespace: modalima
spec:
  provider: azure
  parameters:
    usePodIdentity: "false"
    clientID: "<CLIENT_ID_IDENTIDAD>"       # identidad federada (Workload Identity)
    keyvaultName: kv-modalima-estudio01
    tenantId: "<TENANT_ID>"
    objects: |
      array:
        - objectName: db-password
          objectType: secret
```
El pod monta el secreto como archivo (y opcionalmente lo sincroniza a un `Secret` de Kubernetes).

### 5.5 Cifrar con tus propias claves (CMK)

```
Storage / SQL / Disco  ──usa──►  clave en Key Vault (CMK)
        │
        └─ identidad administrada con rol "Key Vault Crypto Service Encryption User"
```
Servicios como Storage, SQL y Cosmos soportan CMK. Ojo: si **borras o deshabilitas** la clave, **pierdes acceso a los datos**. Por eso se exige soft delete y purge protection.

### 5.6 Rotación

1. Define **expiración** en cada secreto.
2. Suscríbete al evento "secreto próximo a vencer" (Event Grid).
3. Una Function genera la nueva credencial en el sistema destino y guarda una **nueva versión**.
4. Las apps que piden "la última versión" la toman solas (con una caché corta).

**Patrón de doble credencial:** mantener dos credenciales válidas durante la rotación (A y B) para evitar caídas.

---

## 6. Los mismos conceptos en las otras nubes

### AWS: Secrets Manager + KMS (Java, SDK v2)
```java
try (SecretsManagerClient sm = SecretsManagerClient.create()) {
    String valor = sm.getSecretValue(r -> r.secretId("modalima/prod/db-password"))
                     .secretString();
}
```
```bash
aws secretsmanager create-secret --name modalima/prod/db-password --secret-string '<valor>'
aws kms create-key --description "clave de datos modalima"
```
Permiso mínimo de lectura:
```json
{
  "Effect": "Allow",
  "Action": ["secretsmanager:GetSecretValue"],
  "Resource": "arn:aws:secretsmanager:us-east-1:111122223333:secret:modalima/prod/db-password-*"
}
```
Si el secreto se cifra con una CMK propia, el rol también necesita `kms:Decrypt` sobre esa clave.

### OCI: Vault
```bash
oci vault secret create-base64 --compartment-id <OCID> --vault-id <VAULT_OCID> \
  --key-id <KEY_OCID> --secret-name db-password --secret-content-content <BASE64>
```
Política:
```
Allow dynamic-group AppsPedidos to read secret-bundles in compartment Prod where target.secret.name = 'db-password'
```

### GCP: Secret Manager
```bash
printf '%s' '<valor>' | gcloud secrets create db-password --data-file=-
gcloud secrets add-iam-policy-binding db-password \
  --member="serviceAccount:api-pedidos@mi-proyecto.iam.gserviceaccount.com" \
  --role="roles/secretmanager.secretAccessor"
```
```java
try (SecretManagerServiceClient c = SecretManagerServiceClient.create()) {
    String valor = c.accessSecretVersion(
        SecretVersionName.of("mi-proyecto", "db-password", "latest"))
        .getPayload().getData().toStringUtf8();
}
```

---

## 7. Casos de uso de vida real

### Caso 1 · La contraseña que llegó a Git
- **Problema:** un desarrollador de `ModaLima` subió `application.properties` con la contraseña de la base de datos.
- **Acciones:** rotar la contraseña de inmediato, limpiar el historial, activar el escaneo de secretos del repositorio.
- **Solución estructural:** la contraseña vive en Key Vault y la app la lee con identidad administrada.
- **Lección:** rotar primero, investigar después; y que el secreto no vuelva a estar en el código.

### Caso 2 · Rotación sin caída
- **Problema:** rotar la clave de una API de pagos obligaba a redesplegar y dejaba la tienda caída unos minutos.
- **Solución:** secreto versionado + doble credencial + app que relee el secreto cada pocos minutos.
- **Resultado:** rotación mensual automática sin interrupción.
- **Lección:** diseña la app para **tolerar el cambio de credenciales**.

### Caso 3 · "Borraron la clave y no abre nada"
- **Problema:** alguien eliminó la clave CMK que cifraba el storage de reportes.
- **Causa:** el vault no tenía purge protection.
- **Solución:** se recuperó gracias al soft delete; después se activó purge protection y un bloqueo contra borrado.
- **Lección:** la clave es **tan importante como los datos**: protégela más.

### Caso 4 · Certificado vencido en un sábado
- **Problema:** el certificado TLS del dominio venció y las compras se cayeron.
- **Solución:** certificados en Key Vault con renovación automática y alerta a 30 días del vencimiento.
- **Lección:** el vencimiento de certificados es un incidente evitable.

---

## 8. Qué hacer / qué NO hacer

**Qué hacer**
- Un vault **por aplicación y por entorno** (aísla permisos y límites).
- Usar **RBAC** y dar **solo lectura** a las aplicaciones.
- Activar **soft delete** y **purge protection**.
- Poner **expiración** a los secretos y automatizar la rotación.
- Cerrar el acceso público y usar **Private Endpoint** con DNS privado.
- Enviar los **logs de auditoría** a un workspace central y alertar accesos inusuales.
- Cachear el secreto unos minutos para no saturar el vault.
- Mantener claves de producción en **HSM** si la normativa lo exige.

**Qué NO hacer**
- Guardar secretos en el código, en imágenes de contenedor o en variables sin proteger.
- Compartir un vault entre todos los entornos.
- Dar *Key Vault Administrator* a las aplicaciones.
- Imprimir secretos en los logs.
- Usar el vault para guardar archivos o datos masivos.
- Desactivar la protección de borrado "para limpiar rápido".
- Dejar un secreto sin fecha de vencimiento ni dueño.

---

## 9. IAM y red del módulo

| Quién | Qué necesita | Rol mínimo (Azure) |
|---|---|---|
| Aplicación | Leer secretos | Key Vault Secrets User |
| Aplicación | Cifrar/descifrar con una clave | Key Vault Crypto User |
| Servicio con CMK (Storage, SQL) | Usar la clave | Key Vault Crypto Service Encryption User |
| Operador | Crear y rotar secretos | Key Vault Secrets Officer |
| Equipo de plataforma | Crear el vault | Contributor sobre el RG |
| Auditoría | Ver sin cambiar | Reader + acceso a logs |

Red: vault con **Private Endpoint**, zona `privatelink.vaultcore.azure.net` enlazada a **todas** las VNets que lo usan, y `public network access` deshabilitado. Si necesitas permitir servicios de confianza de Azure, revisa la opción de excepción de firewall y sus implicaciones.

---

## 10. Troubleshooting

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `403 Forbidden` / `Caller is not authorized` | Falta rol RBAC | Roles de la identidad sobre el vault | Asignar *Secrets User* |
| Error `ForbiddenByFirewall` / no conecta | Firewall o acceso público cerrado | Redes del vault | Private Endpoint o IP permitida |
| El nombre resuelve a IP pública | Zona DNS privada sin enlace | `nslookup` desde la app | Enlazar la zona (módulo 02) |
| `SecretNotFound` | Nombre, versión o vault equivocados | Listar secretos | Corregir referencia |
| `SecretDisabled` / vencido | Secreto deshabilitado o expirado | Atributos del secreto | Rotar o reactivar |
| No puedo crear un vault/secreto con el mismo nombre | El nombre está en **soft delete** | `az keyvault list-deleted` | Recuperar (`recover`) o purgar si se permite |
| `429 Too Many Requests` | Demasiadas lecturas | Métricas del vault | Cachear, reducir llamadas |
| La referencia `@Microsoft.KeyVault` aparece sin resolver | La app no tiene identidad o permiso | Estado de la referencia en el portal | Habilitar identidad y dar rol |
| AWS: `AccessDeniedException` en KMS | Falta permiso en la *key policy* | Política de la clave | Añadir el principal a la key policy |
| GCP: `PERMISSION_DENIED` | Falta `secretAccessor` | IAM del secreto | Añadir el binding |

---

## 11. Repaso y entrevista

**Repaso**
1. ¿Qué diferencia hay entre un secreto, una clave y un certificado?
2. ¿Por qué un Contributor sobre el vault no puede leer secretos?
3. ¿Qué es el cifrado de sobre y por qué se usa?
4. ¿Qué protegen soft delete y purge protection?
5. ¿Cómo evitas una caída al rotar una contraseña?

**Entrevista**
- Diseña cómo un pod en AKS obtiene la contraseña de una base de datos sin que esté en el código.
- ¿Qué pasa si se elimina una CMK que cifra datos?
- Compara Secrets Manager y Key Vault: diferencias de rotación y de modelo de permisos.
