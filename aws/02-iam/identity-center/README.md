# AWS · IAM · IAM Identity Center (SSO de personas)

**IAM Identity Center** es la puerta de entrada de las **personas** a AWS: un solo inicio de sesión (con MFA) para muchas cuentas, con permisos temporales según su grupo. Reemplaza a los usuarios IAM con contraseña y claves.

## 1. Qué es

**Analogía:** la **recepción única** de un parque empresarial. Te identificas una vez (tu usuario de la empresa, con MFA), la recepción mira a qué grupos perteneces y te entrega un **pase del día** distinto para cada edificio (cuenta): en el edificio de desarrollo eres «desarrollador», en producción «solo lectura». Al terminar el día el pase caduca solo. Si te vas de la empresa, bastan con quitarte de la lista de personal: todos los pases dejan de renovarse.

```
 Directorio de la empresa (Entra ID / Okta / Google / el propio Identity Center)
        │  SAML (inicio de sesión)  +  SCIM (usuarios y grupos sincronizados)
        ▼
  IAM Identity Center ── portal de acceso: https://d-xxxx.awsapps.com/start
        │  asignación = (grupo) + (conjunto de permisos) + (cuenta)
        ▼
  Cuenta 111122223333  →  rol creado y gestionado: AWSReservedSSO_DesarrolloPlataforma_a1b2c3
        ▼
  Credenciales temporales (consola o CLI: aws sso login)
```

## 2. Cómo funciona por dentro

| Pieza | Qué es | Detalle |
|---|---|---|
| **Instancia** | El servicio activado para la organización | Una por organización, en **una región de origen** que no se puede cambiar después (elígela con cuidado) |
| **Almacén de identidades** | Usuarios y grupos | Propio, o sincronizado desde un proveedor externo por SCIM |
| **Proveedor de identidad externo** | Entra ID, Okta, Google Workspace… | Autentica por SAML; sincroniza por SCIM (o Active Directory) |
| **Conjunto de permisos** (*permission set*) | Plantilla de permisos | Políticas administradas por AWS o por el cliente, política en línea, límite de permisos, duración de sesión (1–12 h) |
| **Asignación** | Grupo/usuario + conjunto de permisos + cuenta | Identity Center crea el rol correspondiente en cada cuenta |
| **Portal de acceso** | Página donde la persona ve sus cuentas y roles | También entrega credenciales para CLI y SDK |
| **Aplicaciones** | SAML para apps propias y de terceros | Mismo inicio de sesión |
| **Atributos para ABAC** | Etiquetas de sesión desde el directorio | Permisos por etiqueta (`departamento`, `proyecto`) |
| **Administración delegada** | Una cuenta de miembro administra Identity Center | Evita usar la cuenta de administración |

### Cómo llega a la CLI y a Java
1. `aws configure sso` crea un perfil con `sso_session`.
2. `aws sso login` abre el navegador, autenticas con MFA y se guarda un token.
3. El SDK de Java resuelve el perfil y **obtiene credenciales temporales** solo (necesita los módulos `sso` y `ssooidc` en el classpath).

### Cuentas de emergencia
Mantén una vía de **emergencia** (*break glass*) fuera de Identity Center: un rol/usuario con MFA físico y alarma en cada uso, por si el proveedor de identidad falla.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| 30 personas, 12 cuentas | **Identity Center** con grupos y conjuntos de permisos |
| Ya hay Entra ID/Okta | Úsalo como fuente (SAML + SCIM) |
| Una aplicación (no una persona) | **No**: rol de servicio / IRSA / Pod Identity |
| Pipeline de CI | **No**: OIDC + rol (capítulo Terraform) |
| Una sola cuenta personal de pruebas | Puede bastar IAM con MFA, pero Identity Center sigue siendo mejor |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **SSO** | Un solo inicio de sesión para muchos destinos |
| **SAML** | Protocolo con el que el directorio dice «esta persona es quien dice ser» |
| **SCIM** | Protocolo que copia usuarios y grupos al servicio |
| **Conjunto de permisos** | Plantilla que se convierte en rol en cada cuenta |
| **Asignación** | Quién + qué permisos + en qué cuenta |
| **Sesión** | Duración de las credenciales (1–12 h) |
| **Portal** | URL de entrada de la empresa |
| **Atributos** | Datos del directorio usados como etiquetas de sesión |

## 5. Cómo se usa
1. Elegir la **región de origen** y activar Identity Center en la organización.
2. Conectar el **proveedor de identidad** (SAML + SCIM).
3. Definir **grupos por función** (`plataforma`, `desarrollo-pedidos`, `lectura-prod`, `auditoria`).
4. Definir **conjuntos de permisos** (`AdministradorPlataforma`, `Desarrollo`, `SoloLectura`, `Auditoria`) con duración de sesión corta para los sensibles.
5. **Asignar** por grupo a las cuentas: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
6. Configurar la CLI: [`ejemplos/cli/sso.sh`](ejemplos/cli/sso.sh).
7. Revisar periódicamente quién tiene qué (ver el informe de [uso en Java](uso-en-java.md)).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Administrador de Identity Center (cuenta delegada) | `sso:*`, `identitystore:*` | — |
| Pipeline | Gestiona conjuntos de permisos y asignaciones | — |
| Personas | — | Lo que diga su conjunto de permisos |
| Auditoría | `sso:List*`, `sso:Describe*`, `identitystore:Describe*` | — |

- **MFA obligatorio** (preferible resistente a *phishing*: llaves FIDO2/passkeys).
- Duraciones de sesión **cortas** para producción y administración (1–4 h).
- **Administrador en producción**: solo bajo demanda, con aprobación y registro.
- Asigna **a grupos, nunca a personas**.
- CloudTrail registra cada inicio de sesión y asunción.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Asignar por grupos del directorio | Asignar usuario por usuario |
| Conjuntos de permisos por función | Un conjunto «AdminTodo» para todos |
| Sesiones cortas y MFA | Sesiones de 12 h en producción |
| Salida automática al quitar del grupo (SCIM) | Gestionar altas y bajas a mano |
| Cuenta de emergencia probada y alarmada | Descubrir en la crisis que no hay acceso |
| Todo como código | Cambiar asignaciones en la consola |
| Usar atributos para ABAC | Un conjunto de permisos por proyecto |

## 8. Límites, costos y versiones
- **Costo:** Identity Center no tiene cargo adicional *(verifica)*; pagas lo que usen las personas.
- **Límites** (verifica): conjuntos de permisos por instancia, asignaciones por cuenta, tamaño de la política en línea, cambios de región de origen no soportados.
- **Terraform:** `aws_ssoadmin_*` y `aws_identitystore_*`. Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
