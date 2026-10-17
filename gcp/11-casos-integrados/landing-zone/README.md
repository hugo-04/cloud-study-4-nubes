# Google Cloud · Caso integrado · Landing zone para una nueva unidad

Café Andino abre una línea de negocio nueva («tostaduría en línea») y necesita, en un día y sin sorpresas: carpetas prod/no-prod, proyectos con facturación y labels, subredes en la **VPC compartida** con CIDR que **no se solape** con nada, grupos con roles en las carpetas, tags de entorno, políticas heredadas, presupuesto y auditoría. Todo como código y **verificado** después.

## 1. Qué es

**Analogía:** abrir una sucursal de una cadena con un manual de apertura: se reserva el local (carpetas y proyectos), se conecta a la red central sin chocar con otras sucursales (CIDR), se dan llaves solo a su personal (grupos), se fija el presupuesto y las cámaras ya vienen instaladas (políticas y sink heredados de la organización).

```
 Planificador (Java) ── lee subredes de los proyectos host ── propone 10.24.0.0/16 libre
        ▼
 Terraform (módulo landing-unidad):
   organización (políticas base, sink de auditoría — heredados)
    └─ carpeta tostaduria
         ├─ carpeta prod     tag entorno=prod   ─ proyecto cafeandino-tostaduria-prod  (servicio de la VPC compartida)
         └─ carpeta no-prod  tag entorno=no-prod ─ proyecto cafeandino-tostaduria-dev
   subredes en el host:  tostaduria-prod 10.24.0.0/17 · tostaduria-dev 10.24.128.0/17
   grupos: tostaduria-admins@, tostaduria-devs@  ·  roles en carpetas
   presupuestos por proyecto · lien en prod
        ▼
 Verificador (Java/CLI): ¿existe todo? ¿CIDR sin solapes? «no se pudo comprobar» = hallazgo
```

## 2. Cómo funciona por dentro

| Pieza | Capítulo |
|---|---|
| Carpetas, proyectos, tags, labels, liens | [09 Jerarquía](../../09-gobierno/jerarquia-etiquetas/README.md) |
| Políticas heredadas | [09 Org Policy](../../09-gobierno/org-policy/README.md) |
| VPC compartida, subredes, conectividad con la central | [01 Red](../../01-red/README.md) |
| Grupos y roles | [02 IAM](../../02-iam/README.md) |
| Presupuestos | [09 Costos](../../09-gobierno/presupuestos-costos/README.md) |
| Estado y pipelines | [10 Terraform](../../10-terraform/README.md) |

### Orden de creación
1. Planificar CIDR (leer lo existente: subredes primarias **y secundarias**, más redes locales).
2. `plan` del módulo de la unidad → revisión → `apply` por el pipeline de plataforma.
3. Verificar: cada pieza existe y cumple; los fallos de lectura cuentan como hallazgos.
4. Entregar: proyectos, grupos, bucket de estado propio y pipeline del equipo.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Nueva unidad, equipo o producto | Este módulo |
| Una prueba de concepto de dos semanas | Proyecto en la carpeta sandbox |
| Una cuenta de un proveedor externo | Organización o carpeta aparte con políticas propias |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **VPC compartida** | Una red en un proyecto host usada por proyectos de servicio |
| **Rango secundario** | Direcciones extra de una subred (pods y servicios de GKE) |
| **Herencia** | Lo de la organización ya aplica a la unidad |
| **Verificación** | Comprobar después, no suponer |
| **Hallazgo desconocido** | Lo que no se pudo comprobar |

## 5. Cómo se usa
1. Módulo de la unidad: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Planificador de CIDR y verificador de solapes en [Java](uso-en-java.md).
3. Verificación por CLI: [`ejemplos/cli/verificar.sh`](ejemplos/cli/verificar.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Pipeline de plataforma | `folderAdmin`, `projectCreator`, `billing.user`, `compute.xpnAdmin` | — |
| `tostaduria-admins@` | `roles/editor` en no-prod, roles concretos en prod | — |
| `tostaduria-devs@` | `roles/viewer` en prod, roles de desarrollo en no-prod | — |
| Planificador | `compute.networkViewer` en proyectos host | — |

- Grupos, no personas; nada de `owner`.
- `roles/compute.networkUser` solo sobre las subredes de la unidad.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Planificar CIDR leyendo lo existente | Elegir «uno que parece libre» |
| Contar los rangos secundarios | Olvidar los pods de GKE |
| Heredar políticas de la organización | Copiarlas en cada unidad |
| Verificar después del apply | Dar por hecho que todo quedó |
| Presupuesto desde el día uno | Esperar a la primera factura |

## 8. Límites, costos y versiones
- **Costo:** la landing zone casi no cuesta; los recursos que vendrán sí *(verifica)*.
- **Límites** (verifica): proyectos por cuenta de facturación, subredes por VPC, proyectos de servicio por host.
- **Terraform:** `google_folder`, `google_project`, `google_compute_shared_vpc_service_project`, `google_compute_subnetwork`, `google_folder_iam_member`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
