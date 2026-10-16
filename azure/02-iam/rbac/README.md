# Azure · IAM · Azure RBAC (roles sobre recursos)

## 1. Qué es

**Azure RBAC (Role-Based Access Control) decide qué puede hacer cada identidad sobre los recursos de Azure.** En el edificio: la identidad (Entra ID) ya mostró su DNI; RBAC es la lista que dice "este gafete abre el piso 3, la sala de servidores no".

Una **asignación de rol** siempre tiene tres partes:

```
   QUIÉN              QUÉ PUEDE HACER          DÓNDE
(principal)    +    (definición de rol)   +   (alcance / scope)
Grupo "Devs"        Storage Blob Data Reader  contenedor "fotos"
```

---

## 2. Cómo funciona por dentro

### 2.1 Los tres elementos
| Elemento | Qué es | Ejemplo |
|---|---|---|
| **Principal** | Usuario, grupo, service principal o managed identity | Grupo `sg-desarrollo` |
| **Definición de rol** | Lista de permisos con nombre | `Reader`, `Storage Blob Data Contributor` |
| **Alcance (scope)** | Dónde aplica; se hereda hacia abajo | Management Group → Suscripción → Resource Group → Recurso |

### 2.2 Anatomía de una definición de rol
```json
{
  "Name": "Lector de Pedidos",
  "Actions":     ["Microsoft.Storage/storageAccounts/read"],                                   // plano de control
  "NotActions":  [],
  "DataActions": ["Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read"],     // plano de datos
  "NotDataActions": [],
  "AssignableScopes": ["/subscriptions/<SUB>"]
}
```
- **Actions / NotActions:** operaciones del plano de control (crear, leer, borrar el recurso).
- **DataActions / NotDataActions:** operaciones del plano de datos (leer un blob, enviar un mensaje).
- Se permite lo que está en `Actions` **menos** lo de `NotActions` (`NotActions` no es un "deny", solo resta de la lista).
- Los comodines (`*`) existen: `Microsoft.Storage/*/read`.

### 2.3 Plano de control vs plano de datos (la confusión nº 2)
| | Plano de control | Plano de datos |
|---|---|---|
| Qué es | Administrar el recurso | Usar su contenido |
| Ejemplo | Crear una cuenta de storage, un Key Vault | Leer blobs, leer secretos, enviar mensajes |
| Rol típico | Owner, Contributor, Reader | Storage Blob Data Reader, Key Vault Secrets User |

> Un **Contributor** puede crear la cuenta de storage pero, con autenticación Entra ID, **no puede leer sus blobs** sin un rol de datos. Y un Owner de la cuenta tampoco, si el recurso exige RBAC de datos.

### 2.4 Roles de uso diario
| Rol | Puede |
|---|---|
| **Owner** | Todo, **incluido asignar roles** |
| **Contributor** | Crear/modificar recursos, **sin** asignar roles |
| **Reader** | Ver |
| **User Access Administrator** | Solo gestionar accesos |
| **Role Based Access Control Administrator** | Asignar roles con condiciones (más acotado que User Access Administrator) |
| **Network Contributor** | Redes |
| **Storage Blob Data Reader / Contributor / Owner** | Datos de blobs |
| **Key Vault Secrets User / Officer** | Leer / administrar secretos |
| **Azure Service Bus Data Sender / Receiver** | Enviar / recibir mensajes |
| **Azure Event Hubs Data Sender / Receiver** | Enviar / recibir eventos |
| **AcrPull / AcrPush** | Bajar / subir imágenes |
| **Azure Kubernetes Service RBAC Reader / Writer / Admin** | Kubernetes API con RBAC de Azure |

> Existen cientos de roles integrados. Busca el más específico antes de crear uno propio.

### 2.5 Herencia
Un rol asignado en un nivel aplica a **todo lo que cuelga debajo**. Por eso: **asigna lo más abajo posible** y a **grupos**.

### 2.6 Evaluación
- Los permisos se **suman**: si cualquier asignación (heredada o directa) permite la acción, se permite.
- Existen **deny assignments**, pero solo las crea Azure (por ejemplo con Blueprints/Managed Apps); no son para uso diario.
- Para **prohibir** cosas, no uses RBAC: usa **Azure Policy** (ver `09-gobierno`).

### 2.7 Condiciones (ABAC)
Puedes acotar una asignación con condiciones, por ejemplo "solo blobs con la etiqueta `proyecto = pedidos`" o "solo el contenedor `entrada`":

```
((!(ActionMatches{'Microsoft.Storage/storageAccounts/blobServices/containers/blobs/read'}))
 OR
 (@Resource[Microsoft.Storage/storageAccounts/blobServices/containers:name] StringEquals 'entrada'))
```
Útil para delegar la administración de roles de forma acotada (rol *RBAC Administrator* con condición).

### 2.8 Propagación
Tras asignar un rol, el permiso puede tardar **unos minutos** en aplicarse. El token ya emitido puede traer información antigua: cierra sesión o espera a que expire.

### 2.9 Elevación temporal (PIM)
Con Entra ID P2, un rol puede ser **elegible**: la persona lo *activa* por un tiempo limitado, con justificación y aprobación. Es la forma recomendada de dar Owner/Contributor a humanos.

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para** dar a personas y aplicaciones el acceso mínimo a recursos de Azure, auditar quién puede qué y delegar la administración por equipo.

**Cuándo NO**
- Para **prohibir** (por ejemplo "no crear IP públicas"): eso es **Azure Policy**.
- Para accesos **dentro de una base de datos** (tablas, filas): se maneja con los permisos de la base (usuarios de base de datos), aunque el *ingreso* puede ser con Entra ID.
- Para autenticar a **clientes finales**: es otro tema (External ID).

---

## 4. Conceptos clave

| Término | Definición simple |
|---|---|
| Role assignment | Principal + rol + alcance |
| Role definition | Lista de permisos con nombre |
| Scope | Dónde aplica (hereda hacia abajo) |
| Action / DataAction | Permiso de control / de datos |
| Built-in / custom role | Rol de Microsoft / rol propio |
| Deny assignment | Negación creada por la plataforma |
| Eligible / Active | Rol disponible para activar / ya activado (PIM) |
| ABAC condition | Condición que acota una asignación |

---

## 5. Cómo se usa

- CLI: [`ejemplos/cli/rbac.sh`](ejemplos/cli/rbac.sh)
- Terraform: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf)
- Java: [`uso-en-java.md`](uso-en-java.md)

**Comprobar qué puede hacer alguien**
```bash
az role assignment list --assignee <OBJECT-ID> --all -o table
az role assignment list --scope <SCOPE> --include-inherited -o table
az role definition list --name "Storage Blob Data Reader" -o json
```
En el portal: recurso → **Access control (IAM) → Check access**.

---

## 6. Seguridad

### Quién puede asignar roles
Solo quien tenga `Microsoft.Authorization/roleAssignments/write` en ese alcance: **Owner**, **User Access Administrator** o **RBAC Administrator**. Limita esa lista al mínimo y exige PIM.

### Políticas y controles
- Azure Policy: auditar asignaciones de **Owner** a nivel de suscripción y a cuentas invitadas.
- **Activity Log:** envía los eventos de `roleAssignments/write` a un workspace con alerta.
- **Access reviews** trimestrales para accesos privilegiados.
- Identidades de aplicación: usa **managed identities**, no service principals con secreto.

---

## 7. Qué hacer

- Asignar a **grupos**, no a personas.
- Alcance **mínimo** (recurso o RG).
- Rol **más específico** (el de datos que necesita, no Contributor).
- Dar humanos privilegiados por **PIM**.
- Documentar cada rol personalizado y revisarlo.
- Esperar la propagación antes de concluir que falló.

## 8. Qué NO hacer

- Asignar **Owner** o **Contributor** a nivel de suscripción "para que funcione".
- Pensar que Contributor puede leer datos.
- Crear roles personalizados con `*` en `Actions`.
- Dar permisos a cuentas personales de desarrolladores en producción de forma permanente.
- Mezclar prohibiciones (Policy) con permisos (RBAC).

---

## 9. Límites, costos y versiones

- RBAC no tiene costo (PIM sí requiere licencia).
- Hay un límite de asignaciones por suscripción/Management Group: consulta la cifra vigente; usar grupos ayuda a no agotarlo.
- Los roles integrados se actualizan; verifica los permisos con `az role definition list`.
