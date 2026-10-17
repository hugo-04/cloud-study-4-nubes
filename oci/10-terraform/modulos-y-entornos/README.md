# Oracle OCI · Terraform · Módulos y entornos

Cómo organizar el código de infraestructura para que **prod y no-prod sean iguales en forma y distintos solo en tamaño**: módulos reutilizables con interfaz pequeña, una carpeta (o *stack*) por entorno y componente, variables explícitas y versiones fijadas.

## 1. Qué es

**Analogía:** los planos de una cadena de cafeterías. Hay un plano tipo (módulo) con cocina, barra y baños; cada local (entorno) lo usa con su tamaño y dirección. Si se mejora el plano, se actualiza local por local, empezando por el de prueba.

```
 infra/
  ├─ modulos/
  │    ├─ red-base/         (VCN, subredes, NSG)        versión v1.4.0
  │    └─ microservicio/    (NSG, política, secreto…)   versión v2.1.0
  └─ entornos/
       ├─ no-prod/tienda/   main.tf → module "catalogo" { source = "…microservicio?ref=v2.1.0", replicas = 1 }
       └─ prod/tienda/      main.tf → module "catalogo" { source = "…microservicio?ref=v2.0.3", replicas = 3 }
 Resource Manager (opcional): un stack por carpeta de entorno/componente
```

## 2. Cómo funciona por dentro

### Piezas
| Pieza | Qué es |
|---|---|
| **Módulo** | Carpeta con `variables.tf`, `main.tf`, `outputs.tf`; se llama con `module` |
| **Fuente versionada** | Git con `?ref=vX.Y.Z` o un registro privado; nunca la rama principal sin fijar |
| **Composición raíz** | La carpeta que se aplica (entorno + componente) y tiene su propio estado |
| **Variables con validación** | `validation {}` evita valores absurdos antes de llegar a la API |
| **`for_each`** | Crear varias instancias de un módulo por mapa |
| **Salidas** | Lo que el módulo expone (IDs) para otros componentes |
| **Bloqueo de providers** | `.terraform.lock.hcl` versionado en Git |
| **Resource Manager** | Stacks con variables por entorno, jobs de plan/apply y detección de drift |

### Reglas de diseño
- Un módulo hace **una cosa** con una interfaz pequeña (5–10 variables).
- Entornos distintos = **composiciones raíz distintas** con estados distintos (no `workspaces` para separar prod).
- Diferencias entre entornos solo en variables permitidas (tamaño, réplicas, nombres), nunca en forma.

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Diez microservicios con la misma infraestructura base | Un módulo `microservicio` |
| Probar un cambio de módulo antes de prod | Versionar y subir no-prod primero |
| Un recurso único (el tenancy) | Composición directa, sin módulo |
| Módulo «dios» con 80 variables | **No**: divídelo |
| `workspaces` para separar prod y no-prod | **No**: carpetas y estados separados |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Interfaz del módulo** | Sus variables y salidas |
| **Versión semántica** | Mayor rompe, menor agrega, parche corrige |
| **Promoción** | Mover la misma versión de no-prod a prod |
| **Drift entre entornos** | Prod y no-prod difieren más de lo permitido |
| **`moved`** | Renombrar sin destruir |

## 5. Cómo se usa
1. Módulo [`ejemplos/modulos/microservicio`](ejemplos/modulos/microservicio/main.tf) y composición de prod [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
2. Compara entornos y estado de drift de los stacks de Resource Manager desde [Java](uso-en-java.md).
3. Operación: [`ejemplos/cli/stacks.sh`](ejemplos/cli/stacks.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Autores de módulos | Escritura en el repo de módulos (revisión obligatoria) | — |
| Pipeline por entorno | Permisos solo en el compartimento de su entorno | — |
| Resource Manager | `manage orm-stacks`, `manage orm-jobs` por compartimento | — |

- Los módulos fijan buenas prácticas (NSG mínimos, cifrado, etiquetas obligatorias): seguridad por defecto.
- Revisión de código + `plan` adjunto en cada cambio.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Fijar versiones de módulos y providers | `ref=main` |
| Validaciones en variables | Descubrir errores en el `apply` |
| Promover la misma versión entre entornos | Código distinto por entorno |
| Estados por componente | Un estado por entorno con todo |
| `moved` al refactorizar | Destruir y recrear por un renombre |

## 8. Límites, costos y versiones
- **Costo:** ninguno propio; Resource Manager sin cargo *(verifica)*.
- **Versiones:** provider `oracle/oci ~> 7.0`, OpenTofu/Terraform recientes; fíjalas en `required_version` y el lock.
- **Terraform:** `module`, `moved`, `validation`, `oci_resourcemanager_stack`.
- **SDK:** `ResourceManagerClient` (`oci-java-sdk-resourcemanager`).

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
