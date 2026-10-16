# Azure · Secretos · Key Vault

## 1. Qué es

**Azure Key Vault es una caja fuerte con registro de visitas para tres tipos de objetos: secretos, claves y certificados.** Las aplicaciones no llevan la contraseña en el bolsillo (el código o la configuración): la piden a la caja fuerte con su identidad, y queda anotado quién la pidió y cuándo.

| Objeto | Qué es | Analogía | ¿Sale de la caja? |
|---|---|---|---|
| **Secreto** | Texto privado: contraseña, token, cadena de conexión (hasta 25 KB) | La combinación de una caja | Sí, tu app lo lee y lo usa |
| **Clave (key)** | Material criptográfico (RSA, EC) para cifrar, descifrar, firmar, envolver claves | El molde de una llave | **No**: le pides al servicio que cifre o firme por ti |
| **Certificado** | Certificado X.509/TLS con su ciclo de vida (emisión, renovación) | El carné con fecha de vigencia | Su parte pública sí; la privada queda protegida |

> Un **secreto se lee**; una **clave se usa sin leerla**. Esa diferencia define casi todo el diseño.

### Las variantes del servicio

| Variante | Qué es | Cuándo |
|---|---|---|
| **Key Vault Standard** | Claves protegidas por software | Lo normal para secretos y la mayoría de cifrados |
| **Key Vault Premium** | Claves protegidas por **HSM** (hardware validado) | Normativa que exige HSM |
| **Managed HSM** | Servicio aparte: HSM dedicado, de un solo cliente, con su propio control de acceso | Requisitos regulatorios altos, claves de máxima criticidad |

---

## 2. Cómo funciona por dentro

```
            PLANO DE CONTROL                        PLANO DE DATOS
      (administrar el vault: ARM)             (leer/escribir secretos, claves)
   https://management.azure.com/...          https://<nombre>.vault.azure.net
   roles: Owner, Contributor,                roles: Key Vault Secrets User,
          Key Vault Contributor                     Crypto User, Administrator...
   "crear, borrar, configurar red"           "getSecret, sign, wrapKey..."
```

### 2.1 Dos planos, dos juegos de permisos
- **Plano de control:** crear el vault, cambiar su red, borrarlo. Lo gobierna Azure RBAC con roles como *Contributor* o *Key Vault Contributor*.
- **Plano de datos:** leer un secreto, firmar con una clave. Lo gobiernan roles como *Key Vault Secrets User*.
- Por eso un **Contributor sobre el vault no puede leer secretos**: administra el contenedor, no el contenido.

### 2.2 Cómo se autentica quien llama
1. La aplicación pide un token a Entra ID con la audiencia **`https://vault.azure.net`** (el SDK lo hace por ti).
2. Llama al endpoint `https://<vault>.vault.azure.net` con `Authorization: Bearer <token>`.
3. El vault revisa: ¿el token es válido? → ¿la red está permitida? → ¿el principal tiene un rol con esa acción?

### 2.3 Modelo de permisos: RBAC vs access policies

| | **Azure RBAC (recomendado)** | Access policies (clásico) |
|---|---|---|
| Granularidad | Vault, secreto individual o clave individual (scope) | Solo el vault completo |
| Gestión | Igual que el resto de Azure; condiciones (ABAC) | Política propia del vault |
| Auditoría y PIM | Sí | Limitado |
| Propagación | Puede tardar unos minutos | Más inmediata |

Un vault usa **uno u otro** (propiedad `enableRbacAuthorization`). Para vaults nuevos: RBAC.

| Rol de datos | Para quién |
|---|---|
| **Key Vault Secrets User** | Aplicaciones que **leen** secretos |
| **Key Vault Secrets Officer** | Quien crea, rota y borra secretos |
| **Key Vault Crypto User** | Apps que cifran, firman o envuelven claves |
| **Key Vault Crypto Officer** | Quien administra claves |
| **Key Vault Crypto Service Encryption User** | Servicios (Storage, SQL) que usan tu clave CMK |
| **Key Vault Certificates Officer** | Quien administra certificados |
| **Key Vault Certificate User** | Lee un certificado completo |
| **Key Vault Reader** | Ve metadatos, no valores |
| **Key Vault Administrator** | Control total de datos (uso muy restringido) |

### 2.4 Las piezas internas

| Pieza | Qué hace |
|---|---|
| **Versión** | Cada `set` crea una versión nueva con su identificador; sin versión en la URL se obtiene la **última** |
| **Atributos** | `enabled`, `nbf` (no antes de), `exp` (expira), `tags`, `contentType` |
| **Identificador (URI)** | `https://kv.vault.azure.net/secrets/<nombre>/<versión>` |
| **Soft delete** | Lo borrado queda **recuperable** (7–90 días); siempre activo en vaults nuevos |
| **Purge protection** | Impide el borrado definitivo antes de terminar la retención, incluso al propietario |
| **Cifrado en reposo** | Los objetos se almacenan cifrados; las claves HSM nunca salen del hardware |
| **Registro (logs)** | Categoría `AuditEvent`: quién pidió qué y con qué resultado |
| **Eventos** | Event Grid avisa: `SecretNewVersionCreated`, `SecretNearExpiry`, `SecretExpired`, `KeyNearExpiry`, `CertificateNearExpiry`… |

### 2.5 Claves: operaciones, no lecturas
```
Tu app ──"cifra estos bytes con la clave k1"──► Key Vault ──► bytes cifrados
Tu app ──"firma este hash"──────────────────► Key Vault ──► firma
Tu app ──"envuelve esta clave de datos"─────► Key Vault ──► clave de datos cifrada
```
Operaciones: `encrypt`, `decrypt`, `wrapKey`, `unwrapKey`, `sign`, `verify`. Tipos: RSA (2048/3072/4096) y EC (P-256/384/521); en HSM también claves simétricas (verifica la lista vigente).

**Cifrado de sobre (envelope encryption):** no se manda un archivo de 5 GB al vault. Se genera una **clave de datos** (AES) local, se cifra el archivo con ella, y se **envuelve** (`wrapKey`) esa clave de datos con la clave maestra del vault. Se guarda junto al archivo: el dato cifrado + la clave de datos envuelta. Para leer: `unwrapKey` y descifrar localmente.

**Rotación de claves:** las claves tienen una **política de rotación** (rotar tras N días, avisar antes de expirar). Al rotar se crea una **versión nueva** de la clave; las versiones viejas siguen descifrando lo antiguo.

### 2.6 Certificados: lo que hay por debajo
Un certificado en Key Vault son **tres objetos juntos**: el certificado, una **clave** (la privada) y un **secreto** (el PFX/PEM con todo). Por eso una app puede descargar el certificado con clave privada pidiendo el *secreto* con el mismo nombre.

Emisión: autofirmado, con una CA **integrada** (según la lista vigente, p. ej. DigiCert o GlobalSign) o con una CA propia que tú coordinas. Tiene **acciones de ciclo de vida**: renovar al X % de vida o N días antes de expirar, o solo avisar.

### 2.7 Red
```
Internet ──► firewall del vault (Deny por defecto + IPs permitidas)
VNet     ──► Private Endpoint (subrecurso "vault") + zona privatelink.vaultcore.azure.net
Servicios de confianza de Azure ──► excepción "bypass AzureServices" (revisa cuáles son)
```
Detalle del patrón Private Endpoint + DNS en [Red · Private Endpoint y DNS](../../01-red/private-endpoint-dns/README.md).

### 2.8 Límites de peticiones (throttling)
Cada vault tiene un tope de transacciones por ventana de 10 segundos por tipo de operación; al superarlo responde **429**. El SDK reintenta con espera, pero la solución real es **cachear**. Los valores exactos cambian: *verifica en la documentación oficial "Azure Key Vault service limits"*.

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- Sacar contraseñas, tokens y cadenas de conexión del código y de los repositorios.
- Rotar credenciales sin redesplegar.
- Cifrar datos con claves que tú controlas (CMK).
- Guardar certificados TLS y renovarlos.
- Auditar quién accedió a qué.

**Cuándo NO usarlo**

| Caso | Mejor opción |
|---|---|
| Configuración **no sensible** (URLs, flags, nombres) | **Azure App Configuration** o variables/ConfigMaps |
| Archivos o datos grandes | Guárdalos en **Blob Storage** y deja la **clave** en el vault |
| Millones de lecturas por segundo | Cachea el secreto en memoria unos minutos |
| Evitar contraseñas con servicios de Azure | **Managed Identity**: ni siquiera hay secreto que guardar |

> Orden de preferencia: 1) sin secreto (Managed Identity / Workload Identity), 2) secreto en Key Vault, 3) nunca en el código.

---

## 4. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Vault** | El contenedor; su nombre es único global | `kv-modalima-prod` |
| **Secreto** | Valor privado versionado | `db-password` |
| **Versión** | Cada cambio crea una; "latest" es la última | `.../db-password/3f2a…` |
| **Soft delete** | Papelera: lo borrado se puede recuperar | `az keyvault recover` |
| **Purge protection** | Candado: ni el dueño puede vaciar la papelera antes de tiempo | Obligatorio con CMK |
| **CMK** | Customer-Managed Key: tú controlas la clave con que un servicio cifra tus datos | Storage cifrado con tu clave |
| **Envelope encryption** | Clave de datos local + clave maestra que la envuelve | Cifrar un archivo grande |
| **HSM** | Hardware que guarda la clave sin dejarla salir | Key Vault Premium / Managed HSM |
| **Rotación** | Cambiar el secreto o la clave periódicamente | Cada 90 días |
| **Referencia a Key Vault** | La plataforma resuelve el secreto por ti | `@Microsoft.KeyVault(...)` en App Service |
| **CSI Secrets Store** | Driver que monta secretos como archivos en un pod | Add-on de AKS |

---

## 5. Cómo se usa

### 5.1 Crear un vault seguro
```bash
az keyvault create -g rg-estudio-sec -n kv-modalima-estudio01 -l eastus2 \
  --enable-rbac-authorization true \
  --retention-days 30 \
  --enable-purge-protection true \
  --public-network-access Disabled
```
> Con acceso público deshabilitado no podrás crear secretos desde tu laptop hasta tener Private Endpoint y ruta de red. Para estudiar: `Enabled` con firewall limitado a tu IP, y después cierra.

Todos los comandos (secretos, claves, rotación, certificados, red, logs, eventos): [ejemplos/cli/keyvault.sh](ejemplos/cli/keyvault.sh). Terraform: [ejemplos/terraform/main.tf](ejemplos/terraform/main.tf).

### 5.2 Cuatro formas de que la aplicación lea un secreto

| Forma | Cómo | Se actualiza solo | Cuándo |
|---|---|---|---|
| **A. SDK desde el código** | `SecretClient` + `DefaultAzureCredential` | Si tú relees con caché | Control total, rotación con caché corta |
| **B. Referencia de App Service/Functions** | `@Microsoft.KeyVault(SecretUri=...)` en la configuración | Se actualiza al cambiar la versión (con retraso) | App Service/Functions sin tocar código |
| **C. Secret de Container Apps** | Secreto de la app que apunta a la URL del vault + identidad | Al reiniciar la revisión | Container Apps |
| **D. CSI Secrets Store en AKS** | `SecretProviderClass` monta archivos (y opcionalmente un `Secret` de Kubernetes) | Archivos sí (con rotación activada); variables de entorno **no** hasta reiniciar | Pods |

Ejemplo de B:
```
DB_PASSWORD = @Microsoft.KeyVault(SecretUri=https://kv-modalima-estudio01.vault.azure.net/secrets/db-password/)
```
Si el recurso tiene varias identidades, se indica cuál usa para resolver las referencias (`keyVaultReferenceIdentity`).

Ejemplo de D: [ejemplos/yaml/secretproviderclass.yaml](ejemplos/yaml/secretproviderclass.yaml).

### 5.3 Cifrar tus datos con tu clave (CMK)
```
Storage / SQL / Disco ──usa──► clave en Key Vault
        │
        └─ identidad administrada con "Key Vault Crypto Service Encryption User"
```
Si **borras o deshabilitas** la clave, **pierdes acceso a los datos**. Por eso se exigen *soft delete* y *purge protection* al usar CMK.

### 5.4 Rotación de un secreto
1. Cada secreto lleva **fecha de expiración** y un dueño.
2. Event Grid emite `SecretNearExpiry` (por defecto 30 días antes).
3. Una Function (u otro automatismo) crea la nueva credencial en el sistema destino y guarda una **versión nueva** del secreto.
4. Las apps que piden "latest" lo reciben cuando se vence su caché.

**Patrón de doble credencial:** el sistema destino acepta dos credenciales (A y B) a la vez. Se genera B, se publica como versión nueva, se espera a que todas las apps la usen y recién entonces se revoca A.

---

## 6. Seguridad

### 6.1 IAM (quién necesita qué)

| Quién | Qué hace | Rol mínimo | Alcance |
|---|---|---|---|
| Aplicación | Leer secretos | Key Vault Secrets User | El vault (o el secreto) |
| Aplicación | Cifrar/firmar con una clave | Key Vault Crypto User | La clave |
| Servicio con CMK | Usar la clave | Key Vault Crypto Service Encryption User | La clave |
| Operador | Crear y rotar secretos | Key Vault Secrets Officer | El vault |
| Equipo de plataforma | Crear/configurar el vault | Contributor (o Key Vault Contributor) | El grupo de recursos |
| Auditoría | Ver sin cambiar | Key Vault Reader + acceso a los logs | El vault |

### 6.2 Identidad de la aplicación
Managed Identity o Workload Identity ([IAM](../../02-iam/README.md)); nunca un secreto de cliente para entrar al vault (sería "la llave de la caja fuerte guardada en el escritorio").

### 6.3 Red privada
Private Endpoint (subrecurso `vault`) + zona `privatelink.vaultcore.azure.net` enlazada a **todas** las VNets que lo consultan + acceso público deshabilitado. Verifica con `nslookup` desde la app que el nombre resuelve a una IP privada.

### 6.4 Auditoría
Enviar la categoría **AuditEvent** a Log Analytics; alertar accesos desde principales inesperados, picos de 403/429 y `SecretGet` fuera de horario.

---

## 7. Qué hacer y qué NO hacer

**Qué hacer**
- Un vault **por aplicación y por entorno**: aísla permisos y límites de peticiones.
- **RBAC** y solo lectura para las aplicaciones.
- *Soft delete* y *purge protection* siempre.
- **Expiración** y dueño en cada secreto; automatizar la rotación.
- Cerrar el acceso público y usar Private Endpoint con DNS privado.
- **Cachear** el secreto unos minutos y tolerar el cambio de valor.
- Enviar los logs de auditoría a un lugar central y alertar.
- Reutilizar **un** `SecretClient` por aplicación.

**Qué NO hacer**
- Guardar secretos en código, imágenes, `Dockerfile` o variables sin proteger.
- Compartir un vault entre dev, test y prod.
- Dar *Key Vault Administrator* a las aplicaciones.
- Registrar el valor del secreto en logs.
- Usar el vault como base de datos o almacén de archivos.
- Desactivar la protección de borrado "para limpiar rápido".
- Leer el secreto en **cada petición** HTTP (429 garantizado).
- Dejar secretos sin vencimiento ni dueño.

---

## 8. Límites, costos y versiones

- Tamaño máximo de un secreto: 25 KB. Los nombres admiten letras, números y guiones.
- Se factura por **operaciones** (por cada 10 000), por claves HSM y por renovación de certificados; Managed HSM se factura por hora de pool. *Verifica precios en la página oficial.*
- Límites de transacciones por ventana de 10 s: *verifica "Azure Key Vault service limits"*.
- Los nombres de vault son únicos **globalmente** y quedan reservados mientras estén en *soft delete*.
- SDK Java: `azure-security-keyvault-secrets`, `-keys`, `-certificates` (BOM de Azure SDK 1.3 en estos ejemplos).

Siguiente: [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md).
