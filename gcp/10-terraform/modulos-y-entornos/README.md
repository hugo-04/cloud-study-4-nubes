# Google Cloud · Terraform · Módulos y entornos

Un **módulo** empaqueta un patrón (p. ej. «microservicio en Cloud Run con su cuenta de servicio, sus secretos y su invocador») para que cada equipo lo use igual. Los **entornos** (dev, staging, prod) son **directorios raíz** distintos, cada uno con su backend, sus variables y una versión fija del módulo. Así prod no cambia porque alguien tocó dev.

## 1. Qué es

**Analogía:** planos tipo de una cadena de cafeterías: el plano (módulo) es el mismo; cada local (entorno) decide tamaño y ubicación, y solo cambia de plano cuando la gerencia aprueba la nueva versión.

```
 modulos/microservicio  (v1.4.0, en un repo de módulos o registro privado)
   ├── variables.tf  nombre, imagen, entorno, min/max instancias, secretos, invocadores
   ├── main.tf       google_service_account · google_cloud_run_v2_service · secret IAM · run.invoker
   └── outputs.tf    url, cuenta
 entornos/
   ├── dev/main.tf    module "pedidos" { source = "...?ref=v1.5.0"  min = 0 max = 3 }
   └── prod/main.tf   module "pedidos" { source = "...?ref=v1.4.0"  min = 2 max = 50 }
   (cada uno con su backend gcs y su proyecto)
```

## 2. Cómo funciona por dentro

| Pieza | Qué es |
|---|---|
| **Módulo raíz** | Directorio donde se ejecuta `plan/apply` (uno por entorno y componente) |
| **Módulo hijo** | Reutilizable, recibe variables y expone salidas |
| **Fuente versionada** | `git::...?ref=v1.4.0` o registro privado con `version` |
| **Validaciones** | `validation` en variables, `precondition`/`postcondition` |
| **Proyecto por entorno** | El aislamiento real lo da el proyecto, no solo el directorio |
| **Workspaces** | Útiles para copias efímeras; para entornos prefiere directorios |
| **Provider** | Lo configura el raíz; el módulo solo declara `required_providers` |

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Muchos microservicios iguales | Módulo `microservicio` |
| Prod con tamaño y reglas distintas | Directorio por entorno con variables |
| Probar una versión nueva del módulo | Subir `ref` primero en dev |
| Un recurso único y simple | Sin módulo |
| Envolver un solo recurso sin agregar nada | No hagas un módulo «pasamanos» |

## 4. Conceptos clave
| Término | En simple |
|---|---|
| **Versión fija** | El entorno no cambia hasta que tú subes la versión |
| **Validación** | Rechazar valores inválidos en el `plan` |
| **Salida** | Lo que el módulo devuelve para otros |
| **Promoción** | dev → staging → prod con la misma versión |
| **Deriva** | Cambios hechos fuera de Terraform |

## 5. Cómo se usa
1. Módulo: [`ejemplos/modulos/microservicio/main.tf`](ejemplos/modulos/microservicio/main.tf).
2. Entorno prod que lo usa: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
3. Validación de las variables por entorno y detección de deriva en Cloud Run desde [Java](uso-en-java.md).
4. CLI: [`ejemplos/cli/entornos.sh`](ejemplos/cli/entornos.sh).

## 6. Seguridad
| Identidad | Plano de control | Plano de datos |
|---|---|---|
| Pipeline de dev | Roles en el proyecto de dev | — |
| Pipeline de prod | Roles en el proyecto de prod (aprobación manual) | — |
| Equipos | Pull requests a sus raíces | — |

- Una SA de Terraform por entorno; la de dev no toca prod.
- El módulo crea una SA por servicio con roles mínimos.

## 7. Qué hacer y qué NO hacer
| ✅ Hacer | ❌ No hacer |
|---|---|
| Versionar módulos con etiquetas semánticas | `ref=main` en prod |
| Validaciones en variables | Confiar en que nadie se equivoca |
| Proyecto por entorno | Entornos como prefijos en un proyecto |
| Labels obligatorios desde el módulo | Que cada equipo invente labels |
| Módulos pequeños y con propósito | Un «módulo dios» configurable para todo |

## 8. Límites, costos y versiones
- **Costo:** sin costo propio; el de los recursos creados.
- **Versiones:** Terraform ≥ 1.5 u OpenTofu; `hashicorp/google ~> 8.0` *(verifica)*.
- **Herramientas:** `terraform fmt/validate`, `tflint`, `checkov`/`trivy` en CI.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
