# Google Cloud · IAM · Workload Identity Federation (sistemas externos)

Cómo un sistema **fuera de Google Cloud** —un pipeline de CI, un servidor en tu centro de datos, otra plataforma con un proveedor de identidad OIDC o SAML— obtiene tokens de Google Cloud **sin llaves de cuenta de servicio**: presenta su propio token, Google lo verifica contra un **proveedor** configurado en un **pool** y le entrega un token federado de vida corta.

## 1. Qué es

**Analogía:** un convenio entre universidades. Un estudiante de otra universidad entra a tu biblioteca mostrando su carné (token OIDC); tu biblioteca confía en esa universidad (proveedor), verifica que sea de la carrera correcta (condición) y le da un pase de visitante por el día (token federado).

```
 Pipeline (emisor OIDC) ── token JWT (iss, aud, sub, repository, ref…) ──► STS de Google
                                                                           │ pool "ci" / proveedor "plataforma-ci"
                                                                           │ mapeo de atributos + condición CEL
                                                                           ▼
                                                  token federado (≤ 1 h) ── roles directos al principalSet
                                                                        └─ o suplanta ci-despliegue@… (workloadIdentityUser)
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Workload identity pool** | Contenedor de identidades externas (uno por entorno o por sistema) |
| **Proveedor** | OIDC o SAML: emisor, audiencias permitidas, **mapeo de atributos** y **condición** |
| **Mapeo de atributos** | `google.subject = assertion.sub`, `attribute.repository = assertion.repository`… |
| **Condición** | CEL que **debe** restringir quién entra: `assertion.repository == 'modalima/infra'` |
| **Principal / principalSet** | `principal://…/subject/<sub>` o `principalSet://…/attribute.repository/<valor>` |
| **Archivo de configuración de credenciales** | JSON sin secretos que dice a la biblioteca de dónde sacar el token externo |
| **STS** | Servicio que intercambia el token externo por uno de Google |

### Flujo
1. El sistema externo obtiene su token (por ejemplo, el OIDC del pipeline).
2. La biblioteca (o `gcloud`) llama a STS con ese token según el archivo de configuración.
3. STS valida firma, emisor, audiencia y la **condición**; devuelve un token federado.
4. Con roles directos, ya llama APIs; en modo suplantación, intercambia por un token de la cuenta de servicio.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Pipeline de CI que despliega | **Federación** con condición por repositorio y rama |
| Servidor local con proveedor de identidad corporativo | Federación OIDC/SAML |
| Pod en GKE | **No**: [Workload Identity de GKE](../workload-identity-gke/README.md) |
| Código dentro de Google Cloud | **No**: cuenta adjunta + ADC |
| «No tengo emisor OIDC» | Último recurso: llave con rotación y alcance mínimos |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Emisor (issuer)** | Quién firma el token externo |
| **Audiencia** | Para quién se emitió el token |
| **Afirmación (assertion)** | Los campos del token externo |
| **Condición** | El filtro que impide que cualquiera del emisor entre |
| **Token federado** | Token de Google de vida corta |

## 5. Cómo se usa
1. Pool, proveedor OIDC con condición estricta y roles al `principalSet` del repositorio: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. En el pipeline: `gcloud iam workload-identity-pools create-cred-config …` genera el JSON de configuración (sin secretos): [`ejemplos/cli/federacion.sh`](ejemplos/cli/federacion.sh).
3. Desde Java: valida la condición localmente (pruebas) y obtén credenciales desde el archivo de configuración: [uso en Java](uso-en-java.md).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Admin de IAM | `roles/iam.workloadIdentityPoolAdmin` | — |
| Pipeline (federado) | — | Roles mínimos al `principalSet` de su repositorio/rama |

- **Siempre** una condición: sin ella, cualquier identidad del emisor (por ejemplo, cualquier repositorio de la plataforma de CI) podría entrar.
- Separa pools o condiciones por entorno: la rama principal despliega prod; las ramas de trabajo, solo no-prod.
- Revisa los registros de STS en Audit Logs.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Condición por repositorio **y** rama/entorno | Proveedor sin condición |
| Roles al `principalSet` concreto | Roles a todo el pool |
| Pools separados por entorno | Un pool para todo |
| Archivo de configuración versionado (no tiene secretos) | Llaves JSON en los secretos del CI |
| Tokens de vida corta | Pedir 12 horas «por si acaso» |

## 8. Límites, costos y versiones
- **Costo:** sin cargo.
- **Límites** (verifica): pools y proveedores por proyecto, tamaño del mapeo, vida de tokens.
- **Terraform:** `google_iam_workload_identity_pool`, `google_iam_workload_identity_pool_provider`, `google_project_iam_member` con `principalSet://…`.
- **Java:** `GoogleCredentials.fromStream` con el archivo de configuración (tipo `external_account`) de `google-auth-library`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
