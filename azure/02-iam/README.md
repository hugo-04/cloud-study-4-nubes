# Azure · 02 IAM

Dos mundos, no los mezcles: **quién eres** (Entra ID) y **qué puedes hacer sobre los recursos** (RBAC). Las aplicaciones entran con **Managed Identity** o **Workload Identity**, sin secretos.

| # | Servicio | Qué aprendes |
|---|---|---|
| 1 | [Microsoft Entra ID](entra-id/README.md) | Tenant, usuarios, app registrations, OAuth2/OIDC, JWT, scopes y app roles |
| 2 | [Azure RBAC](rbac/README.md) | Asignaciones de rol, plano de control vs datos, roles personalizados, ABAC |
| 3 | [Managed Identity](managed-identity/README.md) | Identidad de un recurso de Azure sin secretos |
| 4 | [Workload Identity](workload-identity/README.md) | Pods de AKS y pipelines que entran sin secretos |

Cada carpeta trae: teoría, casos reales, uso desde Java, ejemplos (CLI, Terraform, YAML), troubleshooting, repaso y prompt de NotebookLM.
