# AWS · IAM · IRSA y EKS Pod Identity

Cómo un **pod** de Kubernetes (EKS) obtiene **credenciales de AWS sin claves**, con permisos **solo para ese pod**. Hay dos mecanismos: **IRSA** (IAM Roles for Service Accounts) y **EKS Pod Identity**. Al final se incluye el equivalente en ECS, Lambda y EC2 para que veas el patrón completo.

## 1. Qué es

**Analogía:** cada pod es un empleado en una oficina compartida (el nodo). Sin esto, **todos** usarían el pase del edificio (el rol del nodo) y cualquiera podría entrar a cualquier sala. Con IRSA o Pod Identity, **cada empleado recibe su propio pase** según su puesto (ServiceAccount): el de pedidos abre la sala de pedidos, el de facturas abre la de facturas.

```
 Sin identidad por pod:  pod ─► IMDS del nodo ─► rol del NODO (demasiado amplio, compartido)

 IRSA:       pod ─► token del ServiceAccount (OIDC) ─► STS AssumeRoleWithWebIdentity ─► rol del pod
 Pod Identity: pod ─► agente local 169.254.170.23 ─► EKS Auth API ─► credenciales del rol asociado
```

## 2. Cómo funciona por dentro

### IRSA (IAM Roles for Service Accounts)
1. El clúster EKS tiene un **emisor OIDC** (URL pública del clúster). Lo registras en IAM como **proveedor de identidad OIDC**.
2. Creas un **rol** cuya **política de confianza** acepta a ese proveedor con las condiciones:
   - `sub` = `system:serviceaccount:<namespace>:<serviceaccount>` (**el pod exacto**)
   - `aud` = `sts.amazonaws.com`
3. Anotas el ServiceAccount: `eks.amazonaws.com/role-arn: arn:aws:iam::...:role/...`.
4. Un *webhook* del clúster inyecta en el pod: variables `AWS_ROLE_ARN`, `AWS_WEB_IDENTITY_TOKEN_FILE` y un **token proyectado** (JWT, se renueva).
5. El SDK lee el token y llama a **`AssumeRoleWithWebIdentity`**; obtiene credenciales temporales y las refresca.

### EKS Pod Identity
1. Instalas el complemento **EKS Pod Identity Agent** (DaemonSet en cada nodo).
2. Creas un rol con confianza al servicio `pods.eks.amazonaws.com` (acciones `sts:AssumeRole` y `sts:TagSession`).
3. Creas una **asociación** (clúster + namespace + ServiceAccount + rol) con la API de EKS. **No hay anotaciones ni proveedor OIDC.**
4. El pod recibe variables `AWS_CONTAINER_CREDENTIALS_FULL_URI` (agente local) y `AWS_CONTAINER_AUTHORIZATION_TOKEN_FILE`.
5. El SDK pide credenciales al agente (mecanismo de «credenciales de contenedor»), que las obtiene de EKS.
6. Las sesiones llevan **etiquetas de sesión** (clúster, namespace, ServiceAccount, pod…) útiles para ABAC.

### Comparación

| Aspecto | IRSA | Pod Identity |
|---|---|---|
| Configuración | OIDC por clúster + anotación + confianza con `sub` | Complemento + **asociación** por API |
| Reutilizar un rol en varios clústeres | Hay que añadir cada emisor OIDC a la confianza (límite de tamaño) | **Mismo rol, misma confianza** |
| Etiquetas de sesión (ABAC) | No | **Sí** |
| Fargate | **Sí** | No *(verifica)* |
| Requisitos del SDK | Antiguo y estable | SDK reciente *(verifica la versión mínima)* |
| Llamadas a STS desde el pod | Sí (cada pod) | No: las hace el agente |
| Acceso entre cuentas | Por confianza entre cuentas | Rol de destino (*role chaining* gestionado) *(verifica)* |
| Cuándo | Fargate, clústeres existentes, SDK antiguos | Recomendado para clústeres nuevos en EC2 |

### El mismo patrón en otros cómputos
| Cómputo | Identidad del workload |
|---|---|
| **ECS** | **Rol de tarea** (el que usa tu código) y **rol de ejecución** (el que usa ECS para bajar la imagen y escribir logs) |
| **Lambda** | **Rol de ejecución** de la función |
| **EC2** | **Perfil de instancia** (por IMDS) |
| **EKS** | IRSA o Pod Identity (nunca el rol del nodo para la app) |

### El riesgo del rol del nodo
Un pod sin identidad propia puede pedir credenciales al **IMDS** del nodo y obtener el rol del nodo. Mitigación: **IMDSv2 obligatorio**, **límite de saltos = 1** (los pods no alcanzan el IMDS) y, en EKS, el rol del nodo con permisos mínimos.

### Cómo las encuentra el SDK de Java (orden de la cadena por defecto)
1. Propiedades del sistema → 2. Variables de entorno (`AWS_ACCESS_KEY_ID`…) → 3. **Token de identidad web** (IRSA) → 4. Perfiles (`~/.aws`, SSO) → 5. **Credenciales de contenedor** (ECS y Pod Identity) → 6. IMDS (EC2).

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Un pod lee de S3 y escribe en SQS | **Pod Identity** (o IRSA) con rol mínimo |
| Un pod en Fargate | IRSA |
| Muchos clústeres con el mismo rol | Pod Identity |
| Un pod necesita cualquier permiso con claves en un Secret | **No**: elimina las claves |
| Toda la app usa el rol del nodo | **No**: hay que separar por ServiceAccount |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **ServiceAccount** | Identidad de un pod dentro de Kubernetes |
| **OIDC** | Estándar para que un emisor (el clúster) firme tokens de identidad |
| **Token proyectado** | JWT que el clúster monta en el pod y renueva |
| **Asociación** | Vínculo (clúster, namespace, ServiceAccount) → rol |
| **Etiquetas de sesión** | Metadatos del pod enviados en la sesión |
| **Agente de Pod Identity** | DaemonSet que sirve las credenciales |
| **IMDS** | Servicio de metadatos del nodo (169.254.169.254) |
| **Rol de tarea/ejecución** | Los dos roles de ECS |

## 5. Cómo se usa
1. Elige el mecanismo (por defecto, **Pod Identity**; **IRSA** si Fargate).
2. Crea el **rol** con permisos mínimos: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
3. **Pod Identity:** complemento + asociación; **IRSA:** proveedor OIDC + anotación.
4. Manifiestos: [`ejemplos/k8s/`](ejemplos/k8s/).
5. Verifica: [`ejemplos/cli/verificar.sh`](ejemplos/cli/verificar.sh) y `GetCallerIdentity` desde el pod ([uso en Java](uso-en-java.md)).
6. Cierra el IMDS a los pods.

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Pipeline | Crea roles y asociaciones (`eks:CreatePodIdentityAssociation`, `iam:*Role*` acotado) | — |
| Pod | — | Solo los permisos de **su** rol |
| Rol del nodo | Mínimo (ECR de lectura, CNI, logs) | — |
| Seguridad | Describe asociaciones y roles | — |

- **Un ServiceAccount por aplicación** (no `default`) y **un rol por ServiceAccount**.
- IRSA: la confianza debe fijar **`sub` y `aud`** (sin `sub` cualquier pod del clúster podría asumir el rol).
- Pod Identity: la asociación fija namespace + ServiceAccount.
- IMDSv2 obligatorio y salto 1. Políticas de red que impidan llegar al IMDS.
- Rotación: nada que rotar; los tokens y credenciales son temporales.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Un ServiceAccount y un rol por aplicación | Compartir un rol entre 20 servicios |
| `sub` y `aud` en la confianza de IRSA | Confiar en el proveedor sin condición `sub` |
| Pod Identity en clústeres nuevos | Montar claves de acceso en un Secret |
| Rol del nodo mínimo | Dar permisos de aplicación al rol del nodo |
| IMDSv2 y salto 1 | Dejar el IMDS accesible desde pods |
| SDK actualizado | Un SDK antiguo que no entiende credenciales de contenedor |
| Todo como código | Anotar ServiceAccounts a mano |

## 8. Límites, costos y versiones
- **Costo:** sin cargo adicional por IRSA ni Pod Identity.
- **Límites** (verifica): asociaciones por clúster, tamaño de la política de confianza (cada emisor OIDC la agranda).
- **Terraform:** `aws_eks_pod_identity_association`, `aws_iam_openid_connect_provider`, `aws_iam_role`. Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
