# Azure · IAM · Workload Identity (pods de AKS y pipelines sin secretos)

## 1. Qué es

**Workload Identity Federation permite que una carga de trabajo externa a Entra ID (un pod de AKS, un pipeline de GitHub Actions) se haga pasar por una identidad de Azure sin guardar ningún secreto.** En lugar de darle una contraseña, Entra ID **confía en el emisor** del token de la carga de trabajo y lo cambia por un token de Azure.

**Analogía:** tu empresa tiene un convenio con el edificio vecino: "si el portero del vecino firma este pase diciendo que es el técnico X, nuestra recepción lo trata como el técnico X". No hay credencial que compartir: hay **confianza entre emisores**.

---

## 2. Cómo funciona por dentro

### 2.1 En AKS (pod → identidad de Azure)

```
                        ┌──────────────────────────────┐
   1. El kubelet proyecta│ Pod con ServiceAccount "sa-api"│
      un token (JWT) en  │ token en AZURE_FEDERATED_TOKEN_FILE │
      el pod             └───────────────┬───────────────┘
                                         │ 2. el SDK de Azure lee ese token y lo envía a Entra ID
                                         ▼
                              Microsoft Entra ID
                       3. ¿El emisor (OIDC issuer de AKS), el subject
                          "system:serviceaccount:<ns>:<sa>" y la audiencia
                          coinciden con una CREDENCIAL FEDERADA de la identidad?
                                         │ sí
                                         ▼
                       4. entrega un access token de Azure (de la managed identity)
                                         │
                                         ▼
                       5. el pod llama a Storage / Key Vault... con ese token
```

### 2.2 Piezas
| Pieza | Qué es |
|---|---|
| **OIDC issuer del clúster** | URL pública del clúster que firma los tokens de los ServiceAccounts (se habilita en AKS) |
| **Workload Identity (add-on/webhook)** | Componente que inyecta variables y el token proyectado en los pods que lo piden |
| **ServiceAccount de Kubernetes** | La identidad del pod dentro del clúster; lleva la anotación con el `client-id` |
| **User-assigned managed identity** (o app registration) | La identidad de Azure a la que se le dan roles |
| **Federated identity credential** | La regla de confianza: `issuer` + `subject` + `audience` |

### 2.3 Variables que recibe el pod
| Variable | Contenido |
|---|---|
| `AZURE_CLIENT_ID` | El client ID de la identidad (de la anotación del ServiceAccount) |
| `AZURE_TENANT_ID` | Tenant |
| `AZURE_FEDERATED_TOKEN_FILE` | Ruta del token proyectado |
| `AZURE_AUTHORITY_HOST` | Endpoint de Entra ID |

El SDK de Azure (con `DefaultAzureCredential` o `WorkloadIdentityCredential`) las reconoce y hace el intercambio solo.

### 2.4 El `subject` exacto
```
system:serviceaccount:<namespace>:<nombre-del-serviceaccount>
```
Si cambias el namespace o el ServiceAccount, **debes** crear otra credencial federada: la regla es literal.

### 2.5 El mismo mecanismo, otros emisores
| Emisor externo | Subject típico | Uso |
|---|---|---|
| GitHub Actions | `repo:<org>/<repo>:ref:refs/heads/main` o `...:environment:produccion` | Desplegar sin guardar secretos |
| Azure DevOps / otras CI | Según el proveedor | Igual |
| Otro clúster Kubernetes | `system:serviceaccount:...` + su issuer | Cargas multi-clúster |

---

## 3. Para qué sirve y cuándo NO usarlo

**Sirve para**
- Que los **pods** accedan a Key Vault, Storage, Service Bus, SQL… sin secretos.
- **Pipelines** que despliegan a Azure sin guardar credenciales.

**Cuándo NO**
- Cargas que ya corren en un servicio con **managed identity directa** (App Service, Functions, Container Apps, VM): usa la managed identity.
- **Pod identity (v1, aad-pod-identity):** está obsoleto; no lo uses en proyectos nuevos.
- Si no puedes habilitar el OIDC issuer en el clúster.

---

## 4. Conceptos clave

| Término | Definición simple |
|---|---|
| OIDC issuer | URL del emisor de tokens del clúster |
| Federated credential | Regla "confío en este emisor+subject para actuar como esta identidad" |
| Subject | Quién es la carga de trabajo para el emisor |
| Audience | Para quién va el token (normalmente `api://AzureADTokenExchange`) |
| Projected service account token | Token de corta vida inyectado en el pod |
| Token exchange | Cambiar el token del emisor por uno de Azure |

---

## 5. Cómo se usa

- CLI y manifiestos: [`ejemplos/cli/workload-identity.sh`](ejemplos/cli/workload-identity.sh) y [`ejemplos/yaml/`](ejemplos/yaml/)
- Terraform: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf)
- Java: [`uso-en-java.md`](uso-en-java.md)

Pasos:
1. Habilitar en AKS el **OIDC issuer** y **workload identity**.
2. Crear (o reutilizar) una **managed identity user-assigned**.
3. Darle los **roles** que necesita.
4. Crear la **credencial federada** con issuer, subject y audience.
5. Crear el **ServiceAccount** con la anotación del `client-id`.
6. Poner en el pod la etiqueta `azure.workload.identity/use: "true"` y `serviceAccountName`.

---

## 6. Seguridad

### IAM
| Necesidad | Rol |
|---|---|
| Habilitar OIDC/workload identity en AKS | Contributor sobre el clúster (u rol específico de AKS) |
| Crear la identidad y la credencial federada | Managed Identity Contributor |
| Dar roles de datos a la identidad | Quien pueda asignar roles |
| Kubernetes: crear el ServiceAccount | RBAC de Kubernetes en el namespace |

### Buenas prácticas
- Un **ServiceAccount e identidad por aplicación**, con roles mínimos.
- Credenciales federadas **acotadas** (namespace + ServiceAccount exactos; para GitHub, repositorio + rama/entorno).
- Entornos protegidos con aprobación en GitHub para producción.
- Monitorear los **sign-in logs de service principals** de Entra ID.

### Red
El intercambio de tokens va contra Entra ID (`login.microsoftonline.com`): con clúster de salida restringida, permite ese destino. El acceso al servicio (Key Vault, etc.) sigue las reglas de red normales.

---

## 7. Qué hacer

- Habilitar OIDC issuer y workload identity en AKS desde el día 1.
- Subject exacto y por entorno.
- Usar `DefaultAzureCredential` en el código.
- Probar con un pod de diagnóstico que imprima el token (solo el `sub`/`aud`, no el token completo).

## 8. Qué NO hacer

- Reutilizar un ServiceAccount con credencial federada para varias apps.
- Usar el namespace `default`.
- Dejar secretos (`AZURE_CLIENT_SECRET`) en el pod: tendrían prioridad sobre la federación en `DefaultAzureCredential`.
- Usar `aad-pod-identity` (obsoleto).
- Crear credenciales federadas con subjects amplios.

---

## 9. Límites, costos y versiones

- Sin costo adicional.
- Hay un límite de credenciales federadas por identidad (verifica la cifra vigente).
- Los nombres de etiquetas/anotaciones y los flags de CLI han evolucionado (antes se instalaba un webhook aparte; hoy hay add-on administrado): verifica en la doc actual.
- El token de Entra ID puede tardar unos segundos en estar disponible tras crear la credencial federada.
