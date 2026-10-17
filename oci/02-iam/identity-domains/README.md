# Oracle OCI · IAM · Identity Domains (usuarios, grupos y MFA)

Un **identity domain** es el «directorio de personas» de OCI: ahí viven los usuarios, los grupos, las contraseñas, el MFA y la federación con el proveedor de identidad de tu empresa. Las políticas ([unidad anterior](../politicas-compartimentos/README.md)) deciden qué puede hacer cada grupo; el dominio decide **quién eres**.

## 1. Qué es

**Analogía:** la recepción del edificio. Comprueba tu identidad (documento + segundo factor), te entrega una credencial y te anota en un grupo. Luego las puertas (políticas) miran tu grupo.

```
 Persona ──► Identity Domain ──► (contraseña + MFA / SSO con tu IdP)
                 │                       │
              grupos ◄───────────────────┘
                 ▼
         Política: Allow group 'Dominio'/'Grupo' to …
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Dominio** | Contenedor aislado de identidades, con su propia URL (`https://idcs-xxxx.identity.oraclecloud.com`) |
| **Dominio `Default`** | Viene con el tenancy; puedes crear otros (por ejemplo uno por entorno o por socio) |
| **Usuario** | Persona o cuenta técnica con credenciales |
| **Grupo** | Conjunto de usuarios; es lo que citan las políticas |
| **Proveedor de identidad (IdP)** | Tu directorio corporativo, conectado por SAML/OIDC para SSO |
| **MFA** | Segundo factor: app de autenticación, notificación móvil, FIDO2… |
| **Aplicación confidencial** | Cliente OAuth2 del propio dominio para tus servicios |
| **Políticas de inicio de sesión** | Reglas: quién entra, desde dónde y con qué factor |

### Dos APIs
- **API de OCI IAM** (`IdentityClient`): compartimentos, políticas, grupos dinámicos.
- **API SCIM del dominio** (`IdentityDomainsClient`): usuarios y grupos **del dominio**, con **su propia URL** como endpoint.

### Cómo se nombran los grupos en las políticas
`Allow group 'Default'/'Desarrollo' to …` (dominio / grupo). Sin el prefijo se asume `Default`.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Empleados con SSO corporativo | Federación SAML/OIDC + grupos mapeados |
| MFA obligatorio para humanos | Política de inicio de sesión |
| Separar entornos o socios | Un dominio por frontera |
| Cuentas para **aplicaciones** | **No** usuarios con claves: principales de instancia/workload ([unidad](../dynamic-groups-principals/README.md)) |
| Usuarios compartidos («admin» de todos) | **No** |
| Llaves API de larga vida en laptops | Evítalas; usa sesiones o SSO |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **SCIM** | API estándar para gestionar usuarios y grupos |
| **SSO** | Entras una vez con tu empresa y OCI confía |
| **Federación** | Relación de confianza dominio ↔ IdP |
| **MFA** | Algo que sabes + algo que tienes |
| **Mapeo de grupos** | Grupo del IdP → grupo del dominio |
| **Usuario sin grupo** | No puede nada (política denegada por defecto) |

## 5. Cómo se usa
1. Crea el dominio y los grupos: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Conecta el IdP y mapea grupos (consola o Terraform).
3. Activa MFA en la política de inicio de sesión.
4. Escribe las políticas por grupo ([unidad](../politicas-compartimentos/README.md)).
5. Audita usuarios inactivos o sin grupo desde [Java](uso-en-java.md); CLI en [`ejemplos/cli/dominio.sh`](ejemplos/cli/dominio.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Administradores de identidad | Rol de administrador del dominio (pocas personas, con MFA) | — |
| Personas | Sin acceso administrativo por defecto | Según grupos y políticas |
| Aplicaciones | Aplicaciones confidenciales OAuth2 | Tokens de corta vida |

- **MFA para todos los humanos**, sin excepciones.
- **Offboarding:** desactiva al usuario en el IdP; con SCIM se propaga.
- **Revisión periódica:** usuarios inactivos, sin grupo o con demasiados privilegios.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| SSO con el IdP corporativo | Usuarios locales con contraseña para todos |
| Grupos por rol, no por persona | Permisos asignados a usuarios sueltos |
| MFA obligatorio | MFA «opcional» |
| Pocos administradores | Todos administradores «por si acaso» |
| Auditar inactivos | Cuentas de exempleados vivas |

## 8. Límites, costos y versiones
- **Costo:** el dominio `Default` y el nivel gratuito cubren lo básico; otros tipos de licencia se cobran por usuario *(verifica)*.
- **Límites:** usuarios, grupos y aplicaciones por tipo de licencia *(verifica)*.
- **Terraform:** `oci_identity_domain`, `oci_identity_domains_group`, `oci_identity_domains_user`.
- El dominio tiene su **propia URL**: guárdala como configuración, no la adivines.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
