# 03 · IAM y seguridad de identidad

**IAM** (Identity and Access Management) responde dos preguntas: **¿quién eres?** y **¿qué puedes hacer?** En este módulo: **Microsoft Entra ID + Azure RBAC** y su equivalente en **AWS IAM**, **OCI IAM** y **GCP Cloud IAM**.

---

## 1. Qué es (con analogía)

Un edificio de oficinas con control de acceso:

| En el edificio | En la nube |
|---|---|
| Mostrar tu DNI en recepción | **Autenticación** (probar quién eres) |
| El gafete que abre ciertas puertas | **Autorización** (qué puedes hacer) |
| Gafetes prediseñados: "visitante", "técnico", "gerente" | **Roles** |
| "Solo el piso 3, solo de 8 a 18 h" | **Alcance (scope)** y **condiciones** |
| Gafetes para robots de limpieza | **Identidades de aplicación / máquina** |
| Gafete temporal para un contratista | **Acceso temporal / just-in-time** |

---

## 2. Para qué sirve y cuándo NO usarlo como lo estás usando

**Sirve para:** controlar quién (personas y aplicaciones) puede hacer qué sobre cada recurso, auditar accesos y evitar claves en el código.

**Señales de que lo estás usando mal:**
- Todos son administradores "para no complicarse".
- Las aplicaciones usan claves o contraseñas guardadas en la configuración.
- Un permiso dado "temporalmente" lleva meses.

---

## 3. Conceptos clave

| Término | Definición simple | Ejemplo |
|---|---|---|
| **Principal** | Quien pide acceso | Una persona, un grupo, una aplicación |
| **Autenticación** | Probar la identidad | Usuario + MFA, o un token de la app |
| **Autorización** | Decidir qué se permite | "Puede leer blobs del contenedor `fotos`" |
| **Rol** | Paquete de permisos con nombre | Reader, Contributor, `roles/storage.objectViewer` |
| **Permiso / acción** | Una operación concreta | `blobs/read`, `s3:GetObject` |
| **Alcance (scope)** | Dónde aplica el permiso | Suscripción, grupo de recursos, un recurso |
| **Asignación** | Principal + rol + alcance | "Grupo Devs + Reader + rg-dev" |
| **Política** | Reglas escritas (JSON o texto) | Políticas de AWS, *policy statements* de OCI |
| **Identidad administrada** | Identidad de una app que la nube gestiona sola | Managed Identity, IAM Role, Service Account |
| **Federación** | Confiar en una identidad de otro sistema | GitHub Actions entra a la nube sin claves |
| **Mínimo privilegio** | Solo lo necesario, por el tiempo necesario | Lectura en vez de administración |
| **Token** | Prueba temporal de identidad | JWT (Entra ID), credenciales temporales (STS) |

---

## 4. Mapa de equivalencias

| Concepto | Azure | AWS | OCI | GCP |
|---|---|---|---|---|
| Directorio de personas | Microsoft Entra ID (tenant) | IAM + IAM Identity Center | IAM con Identity Domains | Cloud Identity / Google Workspace |
| Usuarios | Users | IAM users / usuarios de Identity Center | Users | Cuentas Google |
| Grupos | Groups | IAM groups | Groups | Google Groups |
| Identidad de aplicación | Service principal / **Managed Identity** | **IAM Role** | Dynamic group + instance/resource principal | **Service Account** |
| Rol | Role definition | IAM role / managed policy | (no hay roles: se escriben políticas) | Role (básico, predefinido, personalizado) |
| Dónde se aplica | Scope: MG, suscripción, RG, recurso | Cuenta, recurso, org (SCP) | Compartimento | Organización, carpeta, proyecto, recurso |
| Cómo se escribe un permiso | **Role assignment** | **Policy** (JSON) | **Policy statement** (texto) | **IAM binding** |
| Guardarraíl que limita a todos | Azure Policy / deny assignments | **SCP** | Security Zones / políticas de compartimento | **Organization Policy** / deny policies |
| Privilegio temporal | PIM (Privileged Identity Management) | Roles con sesión temporal, Identity Center | Grupos con revisión | IAM Conditions, acceso temporal |
| MFA / acceso condicional | Conditional Access | MFA + políticas con condiciones | MFA + políticas de sign-on | 2-Step Verification, Context-Aware Access |
| Federación desde CI/CD | Federated credentials | OIDC provider + role | Verifica la opción vigente | Workload Identity Federation |
| Auditoría | Activity Log, Entra sign-in logs | CloudTrail | Audit | Cloud Audit Logs |

### Diferencias reales

- **OCI no tiene "roles"**: todo se escribe como política en texto, dirigida a un compartimento.
- **AWS evalúa políticas**: un *deny* explícito siempre gana; sin *allow* explícito, se niega.
- **GCP** da permisos **al principal sobre un recurso**, y se heredan hacia abajo (organización → carpeta → proyecto).
- **Azure** separa dos mundos de roles (directorio y recursos). Se explica abajo.

---

## 5. El mismo permiso en las 4 nubes

**Objetivo:** el grupo `Desarrollo` puede **leer** archivos del contenedor/bucket `fotos` y nada más.

**Azure**
```bash
az role assignment create \
  --assignee-object-id <ID_DEL_GRUPO> --assignee-principal-type Group \
  --role "Storage Blob Data Reader" \
  --scope "/subscriptions/<SUB>/resourceGroups/rg-modalima/providers/Microsoft.Storage/storageAccounts/stmodalima/blobServices/default/containers/fotos"
```

**AWS** (política asociada al rol o grupo)
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "LeerFotos",
      "Effect": "Allow",
      "Action": ["s3:GetObject"],
      "Resource": "arn:aws:s3:::modalima-fotos/*"
    },
    {
      "Sid": "ListarFotos",
      "Effect": "Allow",
      "Action": ["s3:ListBucket"],
      "Resource": "arn:aws:s3:::modalima-fotos"
    }
  ]
}
```

**OCI** (política en texto)
```
Allow group Desarrollo to read objects in compartment Prod where target.bucket.name = 'fotos'
```

**GCP**
```bash
gcloud storage buckets add-iam-policy-binding gs://modalima-fotos \
  --member="group:desarrollo@example.com" \
  --role="roles/storage.objectViewer"
```

---

## 6. Azure en detalle

### 6.1 Dos mundos de roles (la confusión nº 1)

| | Roles de Microsoft Entra ID | Roles de Azure RBAC |
|---|---|---|
| Administran | El **directorio**: usuarios, grupos, aplicaciones | Los **recursos**: VMs, redes, storage |
| Ejemplos | Global Administrator, User Administrator | Owner, Contributor, Reader |
| Alcance | Todo el tenant | MG, suscripción, RG, recurso |

> Ser *Global Administrator* **no** te hace dueño de las suscripciones. Existe una opción de "elevar acceso" para casos de emergencia; úsala con auditoría.

### 6.2 Roles base de recursos

| Rol | Puede |
|---|---|
| **Owner** | Todo, **incluido asignar roles** |
| **Contributor** | Crear y modificar recursos, **sin** asignar roles |
| **Reader** | Ver |
| **User Access Administrator** | Solo gestionar accesos |

### 6.3 Plano de control vs plano de datos (la confusión nº 2)

- **Plano de control:** crear, configurar, borrar el recurso (la cuenta de storage, el Key Vault).
- **Plano de datos:** usar el contenido (leer blobs, leer secretos, enviar mensajes).

> Con autenticación Entra ID, un **Contributor** puede crear una cuenta de storage pero **no leer sus blobs**: necesita un rol de datos.

| Servicio | Rol de datos típico |
|---|---|
| Blob Storage | Storage Blob Data Reader / Contributor / Owner |
| Key Vault (con RBAC) | Key Vault Secrets User (leer), Secrets Officer (administrar) |
| Service Bus | Azure Service Bus Data Sender / Receiver / Owner |
| Event Hubs | Azure Event Hubs Data Sender / Receiver |
| Container Registry | AcrPull / AcrPush |
| AKS | Azure Kubernetes Service RBAC Reader / Writer / Admin |
| Cosmos DB | Roles de datos propios del servicio (Built-in Data Reader/Contributor) |

### 6.4 Alcance y herencia

```
Management Group
  └─ Suscripción
       └─ Resource Group
            └─ Recurso
```
Un rol asignado arriba aplica a todo lo de abajo. Asigna **lo más abajo posible**.

### 6.5 Identidades administradas (Managed Identity)

Una identidad que Azure crea y rota por ti. La app **pide un token** a la plataforma y no guarda ninguna clave.

| | System-assigned | User-assigned |
|---|---|---|
| Ciclo de vida | Nace y muere con el recurso | Independiente |
| Reutilizable | No (1 recurso) | Sí (varios recursos) |
| Cuándo | Un solo servicio la usa | Varios servicios, o permisos preasignados antes de crear el recurso |

```bash
# Crear una identidad y darle lectura de blobs
az identity create -g $RG -n id-api-pedidos
PRINCIPAL=$(az identity show -g $RG -n id-api-pedidos --query principalId -o tsv)

az role assignment create --assignee-object-id $PRINCIPAL \
  --assignee-principal-type ServicePrincipal \
  --role "Storage Blob Data Reader" --scope $STORAGE_ID

# Asignarla a una Web App
az webapp identity assign -g $RG -n app-pedidos \
  --identities $(az identity show -g $RG -n id-api-pedidos --query id -o tsv)
```

### 6.6 Workload Identity en AKS (pods sin claves)

```bash
az aks update -g $RG -n $AKS --enable-oidc-issuer --enable-workload-identity
OIDC=$(az aks show -g $RG -n $AKS --query oidcIssuerProfile.issuerUrl -o tsv)

az identity federated-credential create --name fc-api \
  --identity-name id-api-pedidos -g $RG \
  --issuer $OIDC \
  --subject system:serviceaccount:modalima:sa-api \
  --audiences api://AzureADTokenExchange
```

```yaml
apiVersion: v1
kind: ServiceAccount
metadata:
  name: sa-api
  namespace: modalima
  annotations:
    azure.workload.identity/client-id: "<CLIENT_ID_DE_LA_IDENTIDAD>"
---
# En el pod:
#   labels:
#     azure.workload.identity/use: "true"
#   serviceAccountName: sa-api
```

### 6.7 Seguridad de las personas

| Control | Qué hace | Nota |
|---|---|---|
| **MFA** | Segundo factor | Obligatorio para administradores |
| **Conditional Access** | "Solo desde dispositivos conformes / países permitidos" | Requiere licencia (verifica) |
| **PIM** | Roles privilegiados **temporales** y con aprobación | Requiere licencia (verifica) |
| **Cuentas de emergencia (break-glass)** | Acceso si falla todo lo demás | Excluir de Conditional Access, guardadas y monitoreadas |
| **Revisiones de acceso** | Revisar periódicamente quién sigue necesitando qué | Evita permisos zombis |

### 6.8 Rol personalizado (ejemplo)

```json
{
  "Name": "Lector de Pedidos",
  "IsCustom": true,
  "Description": "Ve la cuenta de storage y lee blobs, nada más.",
  "Actions": [
    "Microsoft.Storage/storageAccounts/read"
  ],
  "DataActions": [
    "Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read"
  ],
  "NotActions": [],
  "AssignableScopes": ["/subscriptions/<SUB>"]
}
```

```bash
az role definition create --role-definition lector-pedidos.json
```

---

## 7. AWS en detalle

### 7.1 Tipos de política

| Tipo | Para qué |
|---|---|
| Basada en identidad | Se asocia a un usuario, grupo o rol |
| Basada en recurso | Se asocia al recurso (bucket policy, cola) |
| **SCP** (Service Control Policy) | Techo máximo para toda una cuenta u OU |
| Permissions boundary | Techo para un rol/usuario concreto |
| Session policy | Limita una sesión temporal |

### 7.2 Cómo se decide (orden)

1. ¿Hay un **deny explícito** en cualquier política aplicable? → **Denegado**.
2. ¿Hay un **allow explícito** (y ningún techo lo bloquea)? → **Permitido**.
3. Si no → **Denegado** (por omisión).

### 7.3 Roles y política de confianza

Un **rol** no tiene contraseña: alguien lo **asume** y recibe credenciales temporales (STS). Quién puede asumirlo lo define la **trust policy**:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": { "Service": "ec2.amazonaws.com" },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

- Máquina virtual → **instance profile** con un rol.
- Pods en EKS → **IRSA** o **EKS Pod Identity**.
- Personas → **IAM Identity Center** (SSO), no usuarios IAM con claves.

### 7.4 Política con condición

```json
{
  "Version": "2012-10-17",
  "Statement": [{
    "Effect": "Allow",
    "Action": ["s3:PutObject"],
    "Resource": "arn:aws:s3:::modalima-subidas/entrada/*",
    "Condition": {
      "IpAddress": { "aws:SourceIp": "203.0.113.0/24" },
      "Bool": { "aws:SecureTransport": "true" }
    }
  }]
}
```

---

## 8. OCI en detalle

### 8.1 Forma de una política

```
Allow <sujeto> to <verbo> <tipo-de-recurso> in <ubicación> [where <condición>]
```

| Parte | Ejemplos |
|---|---|
| Sujeto | `group Desarrollo`, `dynamic-group Apps`, `any-user` |
| Verbo | `inspect` < `read` < `use` < `manage` (cada uno incluye al anterior) |
| Tipo de recurso | `objects`, `buckets`, `instance-family`, `virtual-network-family`, `all-resources` |
| Ubicación | `compartment Prod`, `tenancy` |

Ejemplos:
```
Allow group Desarrollo to read objects in compartment Prod where target.bucket.name = 'fotos'
Allow group Redes to manage virtual-network-family in compartment Prod
Allow dynamic-group AppsPedidos to use secret-family in compartment Prod
```

### 8.2 Identidad de aplicación: dynamic groups

```
# Regla del dynamic group: todas las instancias de este compartimento
ALL {instance.compartment.id = '<OCID_DEL_COMPARTIMENTO>'}
```
Luego se escribe una política para ese *dynamic group*. Para Functions se usa *resource principal*; para OKE, *workload identity*.

### 8.3 Herencia

Una política en un compartimento padre **aplica a los hijos**. La política más alta (tenancy) alcanza todo.

---

## 9. GCP en detalle

### 9.1 Roles

| Tipo | Ejemplo | Uso |
|---|---|---|
| Básico | Owner, Editor, Viewer | **Evitar** (demasiado amplios) |
| Predefinido | `roles/storage.objectViewer` | **Preferido** |
| Personalizado | Definido por ti | Cuando ninguno encaja |

### 9.2 Binding

`principal + rol + recurso` (con condición opcional):

```bash
gcloud projects add-iam-policy-binding mi-proyecto \
  --member="serviceAccount:api-pedidos@mi-proyecto.iam.gserviceaccount.com" \
  --role="roles/pubsub.publisher" \
  --condition='expression=request.time < timestamp("2027-01-01T00:00:00Z"),title=temporal'
```

### 9.3 Service accounts

- Prefiere **cuentas de servicio adjuntas** al recurso (Cloud Run, GKE con Workload Identity) o **suplantación** (*impersonation*).
- **Evita crear llaves JSON**: son credenciales de larga duración.
- Desde fuera de GCP (GitHub Actions, otra nube): **Workload Identity Federation**.

---

## 10. Federación para CI/CD (sin secretos)

Idea: el pipeline (por ejemplo GitHub Actions) presenta un **token OIDC** temporal; la nube confía en él y entrega acceso limitado.

| Nube | Cómo se configura |
|---|---|
| Azure | *Federated credential* en la identidad / app registration (emisor y subject del repositorio) |
| AWS | OIDC provider + rol cuya *trust policy* acota repositorio y rama |
| GCP | Workload Identity Pool + Provider, y permiso de suplantar una cuenta de servicio |
| OCI | Verifica la opción vigente de federación de identidades para cargas de trabajo externas |

Ejemplo de condición en la *trust policy* de AWS:
```json
"Condition": {
  "StringEquals": {
    "token.actions.githubusercontent.com:aud": "sts.amazonaws.com",
    "token.actions.githubusercontent.com:sub": "repo:mi-org/mi-repo:ref:refs/heads/main"
  }
}
```

---

## 11. Ejemplos en Java: ninguna clave en el código

**Azure** (`azure-identity` + `azure-storage-blob`)
```java
BlobServiceClient cliente = new BlobServiceClientBuilder()
    .endpoint("https://stmodalima.blob.core.windows.net")
    .credential(new DefaultAzureCredentialBuilder().build())
    .buildClient();

cliente.getBlobContainerClient("fotos").listBlobs()
       .forEach(b -> System.out.println(b.getName()));
```
`DefaultAzureCredential` prueba varias fuentes: variables de entorno, identidad administrada, tu sesión de `az login`, etc. Por eso funciona igual en tu laptop y en Azure.

**AWS** (SDK v2)
```java
try (S3Client s3 = S3Client.create()) {   // usa la cadena de credenciales por defecto
    s3.listObjectsV2(r -> r.bucket("modalima-fotos"))
      .contents().forEach(o -> System.out.println(o.key()));
}
```

**GCP**
```java
Storage storage = StorageOptions.getDefaultInstance().getService();  // Application Default Credentials
storage.list("modalima-fotos").iterateAll()
       .forEach(b -> System.out.println(b.getName()));
```

**OCI** (principal de instancia)
```java
InstancePrincipalsAuthenticationDetailsProvider auth =
    InstancePrincipalsAuthenticationDetailsProvider.builder().build();
ObjectStorageClient os = ObjectStorageClient.builder().build(auth);
```

---

## 12. Casos de uso de vida real

### Caso 1 · "Soy Contributor y no puedo leer los blobs"
- **Problema:** una desarrolladora de `ModaLima` con rol Contributor no podía abrir los archivos del storage con su usuario.
- **Causa:** Contributor es del **plano de control**; leer datos requiere un rol de **datos**.
- **Solución:** asignar *Storage Blob Data Reader* al grupo, solo sobre el contenedor necesario.
- **Lección:** tener permiso sobre el recurso no es tener permiso sobre sus datos.

### Caso 2 · La clave del storage en una variable de entorno
- **Problema:** la API leía imágenes con una clave de cuenta guardada en la configuración y en el repositorio.
- **Solución:** activar identidad administrada en la aplicación, dar *Storage Blob Data Reader* y quitar el uso de claves (`allowSharedKeyAccess = false`).
- **Resultado:** cero secretos en el repositorio y nada que rotar.
- **Lección:** la mejor clave es la que no existe.

### Caso 3 · Contratista por dos semanas
- **Problema:** una consultora externa necesitaba ver logs y recursos de QA.
- **Solución:** grupo temporal con rol Reader sobre el RG de QA, con **revisión de acceso** y fecha de fin (o PIM si hay licencia).
- **Lección:** todo acceso externo tiene vencimiento.

### Caso 4 · Despliegues sin contraseñas
- **Problema:** el pipeline usaba un secreto de aplicación que vencía y rompía los despliegues.
- **Solución:** federación OIDC: el pipeline presenta su token y obtiene acceso solo al grupo de recursos de despliegue.
- **Lección:** credenciales de corta vida, ligadas a un repositorio y una rama.

---

## 13. Qué hacer / qué NO hacer

**Qué hacer**
- Asignar roles a **grupos**, no a personas sueltas.
- Aplicar **mínimo privilegio** y el alcance más pequeño posible.
- Usar **identidades administradas** / roles / service accounts adjuntas.
- Exigir **MFA** a todo el que administre.
- Dar acceso temporal a lo privilegiado (PIM u otros).
- Revisar accesos periódicamente y borrar los zombis.
- Mantener cuentas de emergencia, monitoreadas.
- Registrar y alertar cambios de roles y políticas.

**Qué NO hacer**
- Dar Owner / Administrator / `Editor` "para que funcione".
- Crear llaves de larga duración (claves de storage, llaves JSON, access keys de IAM).
- Compartir una cuenta entre varias personas.
- Guardar secretos en el repositorio o en variables sin protección.
- Asignar roles a nivel de suscripción cuando basta un grupo de recursos.
- Olvidar que los permisos del **plano de datos** son aparte.
- Cambiar permisos en producción sin dejar trazabilidad.

---

## 14. Troubleshooting

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| Azure: `AuthorizationFailed` / "does not have authorization to perform action" | Falta rol en ese alcance | `az role assignment list --assignee <id> --all -o table` | Asignar el rol mínimo en el alcance correcto |
| Azure: 403 aunque soy Contributor o Owner | Faltaba rol de **datos** | ¿Es una operación de datos? | Asignar el rol de datos correspondiente |
| Se asignó el rol y sigue fallando | El token trae permisos viejos o hay retraso | Esperar unos minutos; volver a iniciar sesión | Renovar el token |
| Azure: `AADSTS…` al iniciar sesión | Problema de Entra (MFA, consentimiento, secreto vencido) | Buscar el código en la documentación de errores | Corregir la causa según el código |
| La identidad administrada no funciona en local | No existe en tu laptop | Ver qué credencial usa `DefaultAzureCredential` | Hacer `az login` o definir variables de desarrollo |
| AWS: `AccessDenied` con el allow correcto | *Deny* explícito, SCP o boundary | IAM Policy Simulator, Access Analyzer | Quitar el deny o ajustar el techo |
| AWS: `not authorized to perform: sts:AssumeRole` | Trust policy no incluye al principal | Revisar la trust policy | Agregar el principal correcto |
| OCI: `404 NotAuthorizedOrNotFound` | OCI devuelve 404 si no tienes permiso (no revela si existe) | Revisar la política y el compartimento | Corregir la política |
| GCP: `403 PERMISSION_DENIED` | Falta el rol en el recurso o en un nivel superior | Policy Troubleshooter | Agregar el binding mínimo |

---

## 15. Repaso y entrevista

**Repaso**
1. ¿Qué diferencia hay entre autenticación y autorización?
2. ¿Por qué un Contributor puede no poder leer blobs?
3. ¿Cuándo usas identidad system-assigned y cuándo user-assigned?
4. ¿Cómo decide AWS entre un allow y un deny?
5. ¿Por qué OCI devuelve 404 cuando no tienes permiso?

**Entrevista**
- Diseña el acceso de una app en AKS a Key Vault y Blob sin ninguna contraseña.
- ¿Cómo darías acceso temporal a un contratista y asegurarías que se retire?
- ¿Qué haces si un pipeline necesita desplegar en tres nubes sin guardar secretos?
