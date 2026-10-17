# Google Cloud · IAM · Cuentas de servicio y suplantación

Una **cuenta de servicio** es la identidad de una aplicación. En producción se **adjunta** al recurso (VM, Cloud Run, función, pod con Workload Identity) y el código obtiene tokens del servidor de metadatos: **sin llaves**. Cuando una persona o un sistema necesita actuar como esa cuenta por un rato, usa **suplantación** (tokens de vida corta), no una llave JSON.

## 1. Qué es

**Analogía:** el gafete de un empleado contratista. El gafete (cuenta de servicio) abre ciertas puertas; se entrega en la recepción cada mañana y vence en la noche (token de 1 hora). Fotocopiarlo (llave JSON) es exactamente lo que no se debe hacer.

```
 Cloud Run "pedidos"  ── adjunta ──► pedidos@modalima-tienda-prod.iam.gserviceaccount.com
     └─ código: ADC → servidor de metadatos → token (1 h) → APIs con sus roles
 Ingeniera (gcloud) ── roles/iam.serviceAccountTokenCreator sobre "despliegue@" ──► token de despliegue (≤ 1 h)
 Pipeline externo ── Workload Identity Federation ──► suplanta "ci@"  (ver la unidad de federación)
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Cuenta de servicio** | Principal `serviceAccount:<nombre>@<proyecto>.iam.gserviceaccount.com`; también es un **recurso** con su propia política |
| **Cuenta adjunta** | La que usa un recurso para llamar APIs (requiere `iam.serviceAccountUser` a quien despliega) |
| **Agentes de servicio** | Cuentas que Google usa en tu nombre (`service-<número>@…`); no las borres |
| **Cuentas por defecto** | Compute Engine por defecto con `editor` heredado: **no la uses** |
| **Llaves** | Pares de llaves descargables; última opción y bloqueables por política de organización |
| **Suplantación** | `generateAccessToken`, `signJwt`, `generateIdToken` mediante IAM Credentials |
| **Cadena de delegación** | Suplantar a través de cuentas intermedias (evítalo salvo necesidad) |

### Roles clave sobre la cuenta
| Rol | Permite |
|---|---|
| `roles/iam.serviceAccountUser` | Adjuntar la cuenta a un recurso (desplegar con ella) |
| `roles/iam.serviceAccountTokenCreator` | Generar tokens como ella (suplantar) |
| `roles/iam.workloadIdentityUser` | Que un principal federado o un KSA de GKE la use |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Cada microservicio con su identidad | Una cuenta por servicio y entorno |
| Ingeniero que prueba con los permisos de la app | Suplantación desde `gcloud` |
| Script de mantenimiento puntual | Suplantación con token de 1 hora |
| Sistema fuera de Google Cloud | Workload Identity Federation, no llaves |
| Compartir una cuenta entre 10 servicios | **No** |
| Usar la cuenta por defecto de Compute | **No** |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Token de acceso** | Credencial de vida corta para llamar APIs |
| **Token de identidad (ID token)** | Prueba de identidad para llamar a Cloud Run/servicios propios |
| **Suplantar** | Obtener tokens de otra cuenta sin su llave |
| **Actuar como** | Adjuntar la cuenta a un recurso (`serviceAccountUser`) |
| **Llave JSON** | Credencial descargable de larga vida: riesgo |

## 5. Cómo se usa
1. Cuenta por servicio, roles mínimos, quién puede desplegarla y quién suplantarla: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Tokens de vida corta con reglas desde [Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/cuentas.sh`](ejemplos/cli/cuentas.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Plataforma | `roles/iam.serviceAccountAdmin` | — |
| Pipeline de despliegue | `roles/iam.serviceAccountUser` sobre las cuentas de sus apps | — |
| Ingenieros de guardia | `roles/iam.serviceAccountTokenCreator` con condición y auditoría | — |

- Política de organización `iam.disableServiceAccountKeyCreation` (y `…KeyUpload`).
- Desactiva la concesión automática de `editor` a cuentas por defecto (`iam.automaticIamGrantsForDefaultServiceAccounts`).
- Audit Logs de datos de IAM Credentials para ver cada suplantación.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Una cuenta por servicio y entorno | Una cuenta «app» para todo |
| Adjuntar la cuenta al recurso | Llaves JSON en contenedores |
| Suplantar con vida corta | Descargar llaves «para probar» |
| `serviceAccountUser` solo a pipelines | Darlo a todo el equipo |
| Deshabilitar antes de borrar | Borrar y romper dependencias |

## 8. Límites, costos y versiones
- **Costo:** sin cargo.
- **Límites** (verifica): cuentas por proyecto, llaves por cuenta, vida máxima de tokens (1 h por defecto, ampliable hasta 12 h con política).
- **Terraform:** `google_service_account`, `google_service_account_iam_member`, `google_project_iam_member`.
- **Java:** `IamCredentialsClient` (`google-cloud-iamcredentials`), `ImpersonatedCredentials` (`google-auth-library`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
