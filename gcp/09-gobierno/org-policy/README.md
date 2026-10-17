# Google Cloud · Gobierno · Organization Policy

Las **políticas de organización** son **barandas** que se aplican sobre la jerarquía, sin importar los permisos IAM de quien actúa: aunque seas `owner`, si la política prohíbe IPs públicas en Cloud SQL, no podrás crearlas. Se definen con **restricciones** (*constraints*) predefinidas o **personalizadas** (CEL sobre campos del recurso) y se heredan, con posibilidad de condicionarlas por **tags**.

## 1. Qué es

**Analogía:** el reglamento del edificio. Da igual que tengas la llave de tu departamento (IAM): el reglamento prohíbe hacer asados en el balcón para todos.

```
 Organización ── iam.allowedPolicyMemberDomains = [C0modalima]   (solo identidades del dominio)
   │            ── compute.vmExternalIpAccess = denegar todo
   │            ── sql.restrictPublicIp = enforce
   ├── carpeta produccion ── gcp.resourceLocations = in:southamerica-locations
   └── carpeta sandbox    ── compute.vmExternalIpAccess: permitir si tag entorno=sandbox (condición)
 Restricción personalizada: custom.gkeSinNodosPublicos (CEL sobre container.googleapis.com/Cluster)
```

## 2. Cómo funciona por dentro

| Pieza | Qué es |
|---|---|
| **Restricción booleana** | Se aplica o no (`enforce`) |
| **Restricción de lista** | Valores permitidos/denegados (ubicaciones, dominios, servicios) |
| **Restricción personalizada** | Condición CEL sobre recursos de servicios compatibles |
| **Política** | Reglas sobre una restricción en un nodo de la jerarquía |
| **Herencia / fusión** | `inheritFromParent` fusiona listas; `reset` vuelve al valor por defecto |
| **Condiciones con tags** | Reglas distintas según `resource.matchTag(...)` |
| **Dry run** | Política en modo simulación que solo registra violaciones |
| **Política efectiva** | El resultado final en un recurso |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Nadie expone VMs ni bases a Internet | `compute.vmExternalIpAccess`, `sql.restrictPublicIp` |
| Datos solo en ciertas regiones | `gcp.resourceLocations` |
| Evitar compartir con cuentas externas | `iam.allowedPolicyMemberDomains` |
| Prohibir llaves de cuentas de servicio | `iam.disableServiceAccountKeyCreation` |
| Dar permisos a personas | IAM, no Org Policy |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Constraint** | La regla que se puede activar |
| **Enforce** | Aplicarla |
| **Dry run** | Probarla sin bloquear |
| **Efectiva** | Lo que realmente aplica tras herencia |
| **Excepción con tag** | Permitir en un subconjunto etiquetado |

## 5. Cómo se usa
1. Línea base en la organización, ubicación en prod y restricción personalizada: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Verificación de la línea base efectiva por proyecto en [Java](uso-en-java.md).
3. CLI: [`ejemplos/cli/orgpolicy.sh`](ejemplos/cli/orgpolicy.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Seguridad | `roles/orgpolicy.policyAdmin` (en la organización) | — |
| Auditoría | `roles/orgpolicy.policyViewer` | — |

- Muy pocas personas con `policyAdmin`; cambios por código revisado.
- Excepciones con tags controlados, nunca desactivando la política en una carpeta entera.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Dry run antes de aplicar | Aplicar directo en la organización |
| Línea base en la organización | Políticas solo en algunos proyectos |
| Excepciones por tag y con fecha | `reset` permanente en una carpeta |
| Restricciones personalizadas para reglas propias | Scripts que «corrigen» después |
| Documentar el porqué de cada política | Políticas sin dueño |

## 8. Límites, costos y versiones
- **Costo:** sin cargo.
- **Límites** (verifica): restricciones personalizadas por organización, servicios compatibles con restricciones personalizadas.
- **Terraform:** `google_org_policy_policy`, `google_org_policy_custom_constraint`.
- **Java:** `google-cloud-orgpolicy` (`OrgPolicyClient.getEffectivePolicy`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
