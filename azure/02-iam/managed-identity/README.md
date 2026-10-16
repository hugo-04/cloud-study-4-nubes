# Azure · IAM · Managed Identity (identidad administrada)

## 1. Qué es

**Una Managed Identity es un gafete para tu aplicación que Azure crea, guarda y renueva por ti.** Tu código nunca ve una contraseña: pide un token a la plataforma y la plataforma se lo da porque sabe en qué recurso corre.

| Antes | Con Managed Identity |
|---|---|
| Un secreto en `application.properties` | No hay secreto |
| Alguien rota el secreto cada año (o nunca) | Azure rota las credenciales |
| El secreto se filtra en un log | No existe nada que filtrar |
| Cada app tiene su "usuario técnico" | Cada recurso tiene su identidad en Entra ID |

---

## 2. Cómo funciona por dentro

```
Tu código (en una VM, App Service, Function, Container App, AKS...)
   │ 1. "dame un token para https://storage.azure.com/"
   ▼
Endpoint local de identidad (solo accesible desde ese recurso)
   │   VM / VMSS:       http://169.254.169.254/metadata/identity/oauth2/token   (IMDS)
   │   App Service/Func: variables IDENTITY_ENDPOINT + IDENTITY_HEADER
   ▼
Microsoft Entra ID  ─ comprueba que ese recurso tiene esa identidad ─►  access token (JWT)
   │
   ▼
Tu código llama al servicio con  Authorization: Bearer <token>
   │
   ▼
El servicio (Storage, Key Vault...) evalúa Azure RBAC sobre el principal de la identidad
```

### Tipos

| | **System-assigned** | **User-assigned** |
|---|---|---|
| Quién la crea | Se activa **en** el recurso | La creas tú como recurso independiente |
| Ciclo de vida | Nace y muere con el recurso | Independiente |
| ¿Reutilizable? | No (1 recurso) | **Sí** (muchos recursos) |
| Cuándo | Un solo servicio la usa | Varios servicios; permisos preasignados antes de crear el recurso; credenciales federadas |

> **Regla práctica:** usa **user-assigned** por defecto en arquitecturas con IaC (puedes asignar los roles *antes* de desplegar el recurso, evitando carreras). Usa system-assigned para casos simples de un recurso.

### Qué recursos la soportan
App Service, Functions, VM y VM Scale Sets, Container Apps, AKS (para el clúster y para los kubelet; los pods usan Workload Identity), Logic Apps, Data Factory, Service Bus, Event Hubs, API Management, y muchos más. Verifica la lista vigente.

### El `client_id` y el `object id`
- **Client ID (appId):** lo usa tu código para elegir **cuál** user-assigned usar si el recurso tiene varias.
- **Principal ID (object id):** lo usas al **asignar roles** (`--assignee-object-id`).

### Tokens
Duran del orden de horas; el SDK los **cachea y renueva**. El servicio de identidad aplica límites de peticiones (evita pedir un token por cada llamada).

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para** que una aplicación en Azure acceda a Storage, Key Vault, Service Bus, SQL, Cosmos DB, etc., sin secretos.

**Cuándo NO**
- Si el código corre **fuera de Azure** (tu laptop, otra nube, on-premises): ahí no existe el endpoint de identidad. Usa `az login` en local o **credenciales federadas** / certificados.
- Pods de **AKS**: usa **Workload Identity** (ver [workload-identity](../workload-identity/README.md)), no el endpoint IMDS del nodo.
- Servicios que no aceptan Entra ID (algunas APIs de terceros): ahí sí necesitas un secreto, guardado en Key Vault.

---

## 4. Conceptos clave

| Término | Definición simple |
|---|---|
| Managed identity | Identidad de un recurso, administrada por Azure |
| System-assigned | Atada al recurso |
| User-assigned | Recurso propio y reutilizable |
| IMDS | Servicio de metadatos del host que entrega tokens a VMs |
| Principal ID | Objeto en Entra ID al que se asignan roles |
| Client ID | ID que usa el código para elegir la identidad |
| Federated credential | Credencial que permite a un emisor externo (GitHub, AKS) actuar como la identidad |

---

## 5. Cómo se usa

- CLI: [`ejemplos/cli/managed-identity.sh`](ejemplos/cli/managed-identity.sh)
- Terraform: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf)
- Java: [`uso-en-java.md`](uso-en-java.md)

Pasos mentales (siempre los mismos):
1. **Crear/activar** la identidad.
2. **Asignarla** al recurso (App Service, Container App, VM...).
3. **Darle roles** (RBAC de datos) en el alcance mínimo.
4. En el código, usar **`DefaultAzureCredential`** (o `ManagedIdentityCredential`) con el `client_id` si es user-assigned.
5. **Probar** y esperar la propagación de roles.

---

## 6. Seguridad

### IAM
| Necesidad | Rol |
|---|---|
| Crear identidades user-assigned | **Managed Identity Contributor** |
| Asignar una identidad a un recurso | **Managed Identity Operator** sobre la identidad (+ permisos en el recurso) |
| Darle permisos a la identidad | Quien tenga `roleAssignments/write` (User Access Administrator / RBAC Administrator) |

### Buenas prácticas
- **Una identidad por aplicación (o por función)**, no una "identidad comodín" con todos los permisos.
- Roles de datos con alcance mínimo.
- Auditar con Activity Log los cambios de identidades y asignaciones.
- Política Azure: exigir identidad administrada en ciertos recursos y **prohibir claves** (por ejemplo `allowSharedKeyAccess = false`).

### Red
La identidad no depende de la red: el endpoint de identidad es local. Pero el servicio destino sí puede estar tras Private Endpoint; asegúrate del DNS (ver carpeta de red).

---

## 7. Qué hacer

- Preferir identidades **user-assigned** con IaC.
- Un `client_id` explícito cuando haya varias identidades.
- Quitar claves y cadenas de conexión con secretos cuando exista alternativa con Entra ID.
- Reutilizar un solo cliente del SDK (que cachea el token).
- Documentar qué roles tiene cada identidad.

## 8. Qué NO hacer

- Darle **Owner/Contributor** "para que funcione".
- Reutilizar una sola identidad para todo.
- Pedir un token en cada petición.
- Asumir que funcionará en local sin `az login`.
- Guardar el `client_id` como si fuera secreto (no lo es; el secreto no existe).

---

## 9. Límites, costos y versiones

- Sin costo.
- Hay límites de identidades user-assigned por suscripción y de credenciales federadas por identidad (verifica la cifra vigente).
- El endpoint de identidad tiene límite de peticiones; el SDK ya cachea.
- Comportamientos distintos por servicio (App Service usa `IDENTITY_ENDPOINT`; VM usa IMDS): el SDK lo resuelve.
