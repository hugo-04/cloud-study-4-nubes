# Azure · IAM · Microsoft Entra ID (identidad y autenticación)

## 1. Qué es

**Microsoft Entra ID (antes Azure Active Directory) es el servicio que guarda "quién es quién" en tu empresa y comprueba que cada quien es quien dice ser.** Es la recepción del edificio: verifica tu DNI (autenticación) y te entrega un gafete digital (token). Qué puertas abre ese gafete lo decide otro mundo (Azure RBAC, ver [rbac](../rbac/README.md)).

| En el edificio | En Entra ID |
|---|---|
| El registro de empleados | **Tenant** (directorio) |
| Una persona | **User** |
| Un área o equipo | **Group** |
| Un robot con credencial propia | **Service principal / Managed Identity** |
| Mostrar el DNI | **Autenticación** (usuario + contraseña + MFA) |
| El gafete que entregan | **Token** (JWT) |
| "Solo desde la oficina o con laptop de la empresa" | **Conditional Access** |

---

## 2. Cómo funciona por dentro

### 2.1 Objetos del directorio
| Objeto | Qué es | Notas |
|---|---|---|
| **Tenant** | Instancia de Entra ID de tu organización, identificada por un `tenant id` (GUID) y dominios (`empresa.onmicrosoft.com`) | Una suscripción de Azure confía en **un** tenant |
| **User** | Persona (miembro, invitado/B2B) | Invitados vienen de otros directorios |
| **Group** | Colección de usuarios/principals | *Security group* para permisos; *Microsoft 365 group* para colaboración. Pueden ser **dinámicos** (por reglas) |
| **App registration** | La "definición" de una aplicación: ID, redirect URIs, permisos que expone o pide | Vive en el tenant "hogar" de la app |
| **Enterprise application / Service principal** | La "instancia" de la app dentro de **tu** tenant, a la que se le dan permisos | Una app registration crea un service principal al usarse |
| **Managed identity** | Service principal administrado por Azure, sin secretos | Ver [managed-identity](../managed-identity/README.md) |

> **App registration vs service principal:** la primera es el plano de la aplicación; la segunda es la instancia con la que de verdad entra y recibe permisos en un tenant.

### 2.2 Protocolos: OAuth 2.0 y OpenID Connect
- **OAuth 2.0** responde "¿qué puede hacer esta aplicación en nombre de alguien o de sí misma?" y entrega un **access token**.
- **OpenID Connect (OIDC)** agrega "¿quién es el usuario?" y entrega un **ID token**.

| Flujo | Cuándo | Quién entra |
|---|---|---|
| **Authorization code + PKCE** | Aplicaciones web/SPA/móviles con usuario | Una persona |
| **Client credentials** | Servicio a servicio (microservicio llama a otro), sin usuario | La aplicación |
| **On-behalf-of (OBO)** | Una API llama a otra API **en nombre del usuario** | Usuario, vía la primera API |
| **Device code** | Dispositivos sin navegador (CLI) | Una persona |
| **Managed identity** | Recurso de Azure obtiene token sin secretos | El recurso |
| Password (ROPC) | **Evitar** | — |

### 2.3 El token (JWT) y sus claims
Un access token es un **JWT**: tres partes (cabecera, carga y firma) en Base64. Claims que debes saber leer:

| Claim | Significa |
|---|---|
| `iss` | Quién lo emitió: `https://login.microsoftonline.com/<tenant>/v2.0` |
| `aud` | Para quién es: la API destino (por ejemplo `api://<client-id>`) — **tu API debe validarlo** |
| `sub` / `oid` | Identificador del usuario/principal (`oid` es el objeto en el directorio) |
| `tid` | Tenant del principal |
| `scp` | Permisos **delegados** (scopes) concedidos, separados por espacio — tokens con usuario |
| `roles` | **App roles** asignados — tokens de aplicación (client credentials) |
| `exp`, `nbf`, `iat` | Caducidad, no antes de, emitido en |
| `azp` / `appid` | La aplicación cliente que pidió el token |

> Un **scope** (`scp`) es "lo que el usuario permitió a la app hacer en su nombre". Un **app role** (`roles`) es "lo que la app puede hacer por sí misma". Los microservicios entre sí suelen usar **app roles**.

### 2.4 Permisos de una API: scopes y app roles
Para proteger tu microservicio con Entra ID:
1. Registras una **app registration** para la API y defines un *Application ID URI* (`api://<id>`).
2. Defines **scopes** (permisos delegados) y/o **app roles** (permisos de aplicación).
3. Registras los **clientes** y les otorgas esos permisos (con **consentimiento** del administrador cuando hace falta).
4. El cliente pide un token con `scope=api://<id>/.default` (client credentials) o con scopes concretos.
5. Tu API **valida** el token: firma, `iss`, `aud`, `exp` y los permisos (`scp`/`roles`).

### 2.5 Protección de personas
| Control | Qué hace | Nota |
|---|---|---|
| **MFA** | Segundo factor | Obligatorio para administradores |
| **Conditional Access** | Reglas "si... entonces exige..." (MFA, dispositivo conforme, ubicación) | Requiere licencia P1 (verifica) |
| **PIM** | Roles privilegiados temporales con aprobación | Requiere licencia P2 (verifica) |
| **Access reviews** | Revisión periódica de quién sigue necesitando qué | Licencia P2 |
| **Cuentas break-glass** | 2 cuentas de emergencia excluidas de CA, monitoreadas | Evitan quedarte fuera |
| **Identity Protection** | Detecta inicios de sesión riesgosos | P2 |

### 2.6 Edición y licencias
Entra ID tiene niveles (Free, P1, P2, y suites). Las funciones como Conditional Access, PIM o revisiones dependen del nivel: **verifica la tabla vigente**.

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**: SSO de personas, proteger APIs con tokens, identidades de aplicación, grupos para asignar roles, acceso condicional.

**Cuándo NO**
- Para clientes finales de una tienda online (consumidores): considera **Microsoft Entra External ID** (producto distinto para clientes) en lugar de crear usuarios en tu directorio corporativo; verifica el producto vigente.
- Para identidades de **recursos de Azure**: usa **Managed Identity**, no un service principal con secreto.

---

## 4. Conceptos clave

| Término | Definición simple |
|---|---|
| Tenant | Directorio de tu empresa |
| Principal | Usuario, grupo, service principal o managed identity |
| App registration | Definición de una aplicación |
| Service principal | Instancia de la app en tu tenant |
| Scope | Permiso delegado (en nombre de un usuario) |
| App role | Permiso de la aplicación misma |
| Consent | Autorización del usuario o admin para esos permisos |
| JWT | Formato del token |
| Audience (`aud`) | La API a la que va dirigido el token |
| Issuer (`iss`) | Quién emitió el token |
| JWKS | Claves públicas con las que se verifica la firma |

---

## 5. Cómo se usa

- CLI: [`ejemplos/cli/entra.sh`](ejemplos/cli/entra.sh)
- Terraform (proveedor `azuread`): [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf)
- Java: [`uso-en-java.md`](uso-en-java.md)

**Inspeccionar un token (solo desarrollo)**
```bash
TOKEN=$(az account get-access-token --resource api://<CLIENT-ID-DE-LA-API> --query accessToken -o tsv)
echo "$TOKEN" | cut -d. -f2 | base64 -d 2>/dev/null | python3 -m json.tool
```
(Nunca pegues tokens reales en sitios externos.)

---

## 6. Seguridad

### Quién puede qué en el directorio (roles de Entra, no de Azure)
| Necesidad | Rol de Entra |
|---|---|
| Administrar usuarios y grupos | User Administrator |
| Registrar aplicaciones | Application Developer / Application Administrator |
| Dar consentimiento de administrador | Cloud Application Administrator / Privileged Role Administrator (según el permiso) |
| Todo el directorio | Global Administrator (**mínimos y con PIM**) |

> Ser Global Administrator **no** da acceso a las suscripciones de Azure. Existe la opción "elevar acceso" para emergencias; úsala con auditoría.

### Buenas prácticas de seguridad
- Menos de 5 Global Administrators, todos con MFA resistente a phishing (claves FIDO2).
- Secretos de aplicación con **vencimiento corto**; mejor **certificados** o **credenciales federadas**.
- Grupos para asignar roles; evita permisos a personas sueltas.
- Registrar y alertar cambios de roles y consentimientos.

---

## 7. Qué hacer

- Validar **siempre** `iss`, `aud`, firma y `exp` en tu API.
- Preferir **app roles** para servicio a servicio, y **scopes** para tokens con usuario.
- Usar **credenciales federadas** o identidades administradas para cargas de trabajo.
- Un registro de aplicación **por API** y **por cliente**.
- Revisar periódicamente aplicaciones con secretos próximos a vencer.

## 8. Qué NO hacer

- Aceptar tokens sin validar la audiencia ("cualquier token del tenant vale").
- Guardar secretos de aplicación sin vencimiento en el repositorio.
- Dar consentimiento de administrador a permisos amplios (`Directory.ReadWrite.All`) sin revisión.
- Usar el flujo de contraseña (ROPC).
- Usar cuentas personales de administradores para aplicaciones.
- Confundir roles de Entra con roles de Azure RBAC.

---

## 9. Límites, costos y versiones

- Hay límites de objetos por tenant, aplicaciones y tamaño de token (muchos grupos pueden exceder el límite del token: usa *group overage*/consulta a Graph).
- Funciones por nivel de licencia: P1/P2 tienen costo por usuario.
- Los tokens duran del orden de una hora (configurable por políticas); no dependas de duración fija.
- Existen dos versiones de endpoints (v1.0 y v2.0): para código nuevo usa **v2.0**.
