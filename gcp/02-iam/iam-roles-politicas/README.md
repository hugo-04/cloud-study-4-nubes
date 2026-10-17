# Google Cloud · IAM · Roles y políticas de permisos

En Google Cloud, **quién puede hacer qué sobre qué** se expresa con **políticas de permisos** (*allow policies*) adjuntas a organización, carpetas, proyectos o recursos: cada política tiene **bindings** que unen un **rol** (conjunto de permisos) con **principales** (usuarios, grupos, cuentas de servicio, identidades federadas), opcionalmente con una **condición**. Se heredan hacia abajo y se **suman**; las **políticas de denegación** restan.

## 1. Qué es

**Analogía:** el llavero de un edificio. Cada llave (rol) abre un conjunto de puertas (permisos); se entrega a personas o equipos (principales) para un piso concreto (recurso) y a veces con horario (condición). Una llave entregada en la portería del edificio (organización) abre esas puertas en todos los pisos.

```
 Organización ─ binding: roles/resourcemanager.organizationViewer → group:auditoria@
   └─ Carpeta tienda ─ binding: roles/viewer → group:tienda-devs@
        └─ Proyecto modalima-tienda-prod
             ├─ roles/run.developer  → group:tienda-devs@   (condición: recurso con tag entorno=prod… )
             └─ Bucket comprobantes ─ roles/storage.objectViewer → serviceAccount:pedidos@…
 Permisos efectivos = unión de lo heredado  −  políticas de denegación
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Permiso** | Acción concreta: `storage.objects.get` |
| **Rol básico** | `owner`, `editor`, `viewer`: enormes; evítalos en producción |
| **Rol predefinido** | De Google por servicio: `roles/pubsub.publisher` |
| **Rol personalizado** | Tu lista de permisos (en organización o proyecto) |
| **Principal** | `user:`, `group:`, `serviceAccount:`, `principal://` / `principalSet://` (federación), `domain:` |
| **Binding** | Rol + miembros (+ condición) |
| **Condición (CEL)** | Expresión sobre recurso, fecha, tags: `resource.name.startsWith(...)` |
| **Política de denegación** | Niega permisos a principales aunque un rol los otorgue *(verifica cobertura)* |
| **PAB (límites de acceso de principal)** | Restringe a qué recursos puede acceder un principal *(verifica)* |
| **ETag** | Control de concurrencia al modificar la política |

### Evaluación
1. Se reúnen las políticas del recurso y de sus ancestros.
2. Se evalúan denegaciones; si alguna aplica, se niega.
3. Si algún binding (con condición verdadera) da el permiso, se permite.

### Herramientas
- **Policy Analyzer**: «¿quién puede hacer X sobre Y?».
- **Recomendador de IAM**: roles con permisos sin usar.
- **Policy Troubleshooter**: por qué a alguien se le negó algo.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Equipo que despliega en Cloud Run de su proyecto | `roles/run.developer` al grupo en el proyecto |
| App que solo lee un bucket | `roles/storage.objectViewer` en el **bucket** |
| Acceso temporal de soporte | Binding con condición de fecha de expiración |
| Prohibir borrar proyectos a todos salvo plataforma | Política de denegación en la organización |
| Dar `owner` «para que funcione» | **Nunca** |
| Usuarios sueltos en políticas | **No**: grupos |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Herencia** | Lo otorgado arriba vale abajo |
| **Mínimo privilegio** | Solo los permisos necesarios, en el recurso más pequeño |
| **Condición** | «Solo si…» |
| **Recomendaciones** | Sugerencias para quitar permisos no usados |
| **Lectura-modificación-escritura** | Leer la política, cambiar y escribir con el ETag |

## 5. Cómo se usa
1. Bindings por grupo, rol personalizado y acceso temporal con condición: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Audita la política del proyecto desde [Java](uso-en-java.md).
3. CLI y Policy Troubleshooter: [`ejemplos/cli/iam.sh`](ejemplos/cli/iam.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Administradores de IAM | `roles/resourcemanager.projectIamAdmin` (o `iam.securityAdmin`) | — |
| Auditoría | `roles/iam.securityReviewer` | — |
| Apps | Roles de datos mínimos por recurso | — |

- Nada de `allUsers`/`allAuthenticatedUsers` salvo contenido público intencional.
- Prefiere `google_*_iam_member` (aditivo) a `*_iam_policy` (reemplaza todo) en Terraform.
- Dos personas para cambios de IAM en producción (revisión de código).

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Grupos como miembros | Usuarios individuales |
| Roles predefinidos o personalizados acotados | Roles básicos |
| Otorgar en el recurso más pequeño | Todo a nivel organización |
| Condiciones para acceso temporal | Permisos «temporales» eternos |
| Revisar recomendaciones mensualmente | Acumular permisos |

## 8. Límites, costos y versiones
- **Costo:** IAM sin cargo.
- **Límites** (verifica): bindings por política, miembros por política, roles personalizados por organización, tamaño de condiciones.
- **Terraform:** `google_project_iam_member`, `google_project_iam_custom_role`, `google_iam_deny_policy`, `google_storage_bucket_iam_member`.
- **Java:** `ProjectsClient.getIamPolicy` (`google-cloud-resourcemanager`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
