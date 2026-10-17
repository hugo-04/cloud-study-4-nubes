# Oracle OCI · Terraform · Autenticación y pipelines

Cómo ejecutar Terraform/OpenTofu contra OCI **sin llaves personales en laptops ni secretos eternos en el CI**: identidades por entorno, *instance principal* o *resource principal* para runners dentro de OCI, usuarios de servicio con llaves rotadas para runners externos, y un pipeline con `plan` revisado antes de `apply`.

## 1. Qué es

**Analogía:** el acceso de los técnicos de mantenimiento a un edificio. En vez de prestarles la llave maestra del dueño, cada empresa contratista recibe una tarjeta propia, válida solo para sus pisos y con vencimiento; y todo trabajo grande se aprueba por escrito antes de empezar.

```
 Pull request ──► pipeline: fmt · validate · tflint · plan (no-prod/prod)  ──► revisión humana del plan
                                                                         │ aprobado
 Runner en OCI (VM/OKE/Container Instance) ── instance/resource principal ──► apply en su compartimento
 Runner externo ── usuario de servicio + API key (Vault, rotada) ──► apply
 Alternativa administrada: Resource Manager (job de plan → aprobación → job de apply)
```

## 2. Cómo funciona por dentro

### Formas de autenticar el provider `oci`
| Modo | Configuración del provider | Cuándo |
|---|---|---|
| **API key** | `auth = "APIKey"` + `~/.oci/config` (usuario, huella, llave) | Personas y runners externos (usuario de servicio) |
| **Instance principal** | `auth = "InstancePrincipal"` | Runner en una VM de OCI (grupo dinámico) |
| **Resource principal** | `auth = "ResourcePrincipal"` | Dentro de servicios que lo exponen (funciones, Container Instances, Resource Manager) |
| **Security token** | `auth = "SecurityToken"` (sesión de `oci session authenticate`) | Personas con SSO, sesiones cortas |
| **OKE workload identity** | `auth = "OKEWorkloadIdentity"` *(verifica)* | Runner como pod en OKE |

### Separación de privilegios
- Una identidad por **entorno** (y a veces por componente): el runner de no-prod **no puede** tocar prod.
- `plan` puede ejecutarse con permisos de lectura (`inspect`/`read`); `apply` con `manage` acotado.
- Aprobación manual entre `plan` y `apply` en prod, aplicando **el mismo** archivo de plan.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Runner propio dentro de OCI | Instance principal + grupo dinámico por entorno |
| CI externo | Usuario de servicio por entorno, API key en el almacén de secretos del CI, rotación ≤ 90 días |
| Equipo sin infraestructura de CI | Resource Manager con stacks y aprobación |
| Personas aplicando en prod desde su laptop | **No** |
| Una llave de API compartida por todo el equipo | **No** |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Usuario de servicio** | Identidad no humana con permisos acotados |
| **Huella (fingerprint)** | Identifica la llave pública cargada |
| **Rotación** | Reemplazar la llave periódicamente sin cortar el servicio |
| **Plan guardado** | `plan -out` que luego se aplica tal cual |
| **Mínimo privilegio** | Solo lo necesario, solo donde hace falta |

## 5. Cómo se usa
1. Grupos dinámicos y políticas por entorno para runners en OCI: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Pipeline de ejemplo con plan revisado y apply del mismo plan: [`ejemplos/pipeline/pipeline.sh`](ejemplos/pipeline/pipeline.sh).
3. Vigila la edad de las API keys de usuarios de servicio desde [Java](uso-en-java.md).
4. Diagnóstico: [`ejemplos/cli/autenticacion.sh`](ejemplos/cli/autenticacion.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Runner no-prod | `manage` en `modalima:no-prod` | Estado: prefijo `no-prod/` |
| Runner prod | `manage` en `modalima:prod` | Estado: prefijo `prod/` |
| Revisores | Lectura del plan | — |
| Administradores IAM | Gestión de usuarios de servicio y llaves | — |

- Ninguna identidad de pipeline con `manage all-resources in tenancy`.
- Llaves privadas en el almacén de secretos del CI o en Vault, nunca en el repo.
- Registra en Audit quién (qué identidad) aplicó cada cambio.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Instance principal en runners de OCI | API keys en runners dentro de OCI |
| Una identidad por entorno | Un súper usuario para todo |
| Rotar llaves y borrar las viejas | Llaves de hace dos años activas |
| `apply` del plan revisado | `apply -auto-approve` en prod |
| `fmt`, `validate`, `tflint` y escaneo de seguridad en cada PR | Revisar solo en el `apply` |

## 8. Límites, costos y versiones
- **Costo:** ninguno propio.
- **Límites** (verifica): API keys por usuario (3), vigencia de tokens de sesión.
- **Terraform:** `oci_identity_dynamic_group`, `oci_identity_policy`, `oci_identity_user`, `oci_identity_api_key`.
- **SDK:** `IdentityClient` (`oci-java-sdk-identity`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
