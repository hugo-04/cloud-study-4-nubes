# Google Cloud · Terraform · Autenticación y pipelines

Terraform en equipo corre en **pipelines**, no en laptops. En Google Cloud el pipeline se autentica **sin llaves** con **Workload Identity Federation** (el token OIDC del sistema de CI se cambia por credenciales de Google) y **suplanta** a una cuenta de servicio de Terraform **por entorno**. El flujo típico: `plan` en cada pull request (con permisos de lectura), revisión humana, `apply` del **mismo plan** al fusionar, con aprobación extra en prod.

## 1. Qué es

**Analogía:** el ingreso del personal de mantenimiento a un edificio: muestran su credencial de la empresa contratista (token OIDC), recepción la valida contra la lista (pool y proveedor) y les entrega una tarjeta temporal de un piso concreto (SA del entorno) que vence en una hora.

```
 Sistema de CI (repo modalima/infra)
   │ token OIDC: repository=modalima/infra, ref=refs/heads/main, environment=prod
   ▼
 Pool "ci-modalima" ─ proveedor "plataforma-ci" (condición: repo y rama)
   │ STS → token federado
   ▼
 principalSet …/attribute.repository/modalima/infra  ──workloadIdentityUser──▶ SA tf-plan-prod (lectura)
                                                                             SA tf-apply-prod (escritura, solo main + aprobación)
   ▼
 plan → artefacto plan.bin + plan.json → revisión → apply plan.bin
```

## 2. Cómo funciona por dentro

| Pieza | Qué es |
|---|---|
| **Pool y proveedor** | Confían en el emisor OIDC del CI con mapeo de atributos y condición CEL |
| **Atributos** | `attribute.repository`, `attribute.ref`, `attribute.environment` |
| **SA de plan** | Lectura (`roles/viewer` + `iam.securityReviewer` + lectura del estado) |
| **SA de apply** | Escritura acotada al proyecto del entorno |
| **Archivo de credenciales** | `external_account` generado por el paso de autenticación; ADC lo usa |
| **Plan guardado** | `terraform plan -out` + `show -json` para revisar y aplicar exactamente eso |
| **Políticas sobre el plan** | Bloquear destrucciones o recursos prohibidos antes del apply |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| CI externo desplegando en Google Cloud | WIF + suplantación |
| Runner dentro de Google Cloud | SA adjunta al runner (sin federación) |
| Desarrollador probando un plan | `gcloud auth application-default login` + suplantación de la SA de plan |
| Llaves JSON de SA en secretos del CI | Nunca (y la política `iam.disableServiceAccountKeyCreation`) |
| Apply desde la laptop en prod | No |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Federación** | Cambiar un token externo por uno de Google |
| **Suplantación** | Actuar como una SA con un token de corta vida |
| **Separación plan/apply** | Leer en PR, escribir solo al fusionar |
| **Plan guardado** | Aplicar exactamente lo revisado |
| **Política del plan** | Reglas automáticas sobre `plan.json` |

## 5. Cómo se usa
1. Pool, proveedor y SAs de plan/apply por entorno: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Pasos del pipeline (genéricos): [`ejemplos/pipeline/pipeline.sh`](ejemplos/pipeline/pipeline.sh).
3. Política sobre el `plan.json` (destrucciones, recursos prohibidos) en [Java](uso-en-java.md).
4. CLI de diagnóstico: [`ejemplos/cli/autenticacion.sh`](ejemplos/cli/autenticacion.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| PR (cualquier rama) | SA de plan: lectura | Lectura del estado |
| main + aprobación | SA de apply: roles del entorno | Escritura del estado |
| Plataforma | `roles/iam.workloadIdentityPoolAdmin` | — |

- Condición del proveedor por repositorio; la de apply, además por rama y entorno.
- Tokens de corta vida; nada de llaves.
- El `plan.json` puede tener secretos: artefacto privado y con expiración.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| SA de plan y de apply separadas | Una SA `owner` para todo |
| Aplicar el plan guardado | Re-planificar en el apply |
| Política automática sobre destrucciones | Revisar a ojo planes de 500 líneas |
| Condición por repo y rama | Un proveedor que acepta cualquier repo |
| Aprobación manual en prod | Apply automático en prod sin revisión |

## 8. Límites, costos y versiones
- **Costo:** WIF y STS sin cargo *(verifica)*.
- **Límites** (verifica): pools por proyecto, proveedores por pool, duración del token.
- **Terraform:** `google_iam_workload_identity_pool`, `google_iam_workload_identity_pool_provider`, `google_service_account_iam_member`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
