# Oracle OCI · 10 Terraform

Toda la infraestructura de los capítulos anteriores, como código que un equipo puede mantener: dónde vive el estado, cómo se organiza el código y quién (qué identidad) lo aplica.

| Unidad | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Estado remoto](estado-remoto/README.md) | ¿Dónde guardo el estado y cómo evito pisarme? | El libro de inventario único | Trabajo en equipo seguro |
| [Módulos y entornos](modulos-y-entornos/README.md) | ¿Cómo reutilizo y mantengo prod igual a no-prod? | Los planos tipo de una cadena | Consistencia y promoción |
| [Autenticación y pipelines](autenticacion-y-pipelines/README.md) | ¿Con qué identidad y con qué controles se aplica? | Tarjetas de contratista | CI/CD sin llaves eternas |

## Árbol de decisión: «quiero…»

```
¿Dónde guardo el estado?
   ├─ Terraform reciente            → backend "oci" en Object Storage (privado, versionado, CMK)
   ├─ OpenTofu / sin backend "oci"  → backend "s3" contra la API compatible de Object Storage
   └─ No quiero gestionar backend   → Resource Manager

¿Cómo organizo el código?
   └─ Módulos versionados + una composición raíz por entorno/componente (estados separados)

¿Quién aplica?
   ├─ Runner dentro de OCI  → instance/resource principal o workload identity
   ├─ Runner externo        → usuario de servicio por entorno, llave rotada
   └─ Sin CI propio         → Resource Manager con aprobación
```

## Comparativa

| Característica | Object Storage (`oci`/`s3`) | Resource Manager |
|---|---|---|
| **Quién ejecuta** | Tu CI/runner | El servicio |
| **Estado** | Tu bucket | Administrado en el stack |
| **Bloqueo** | Según backend | Un job a la vez |
| **Drift** | `plan -refresh-only` | Detección integrada |
| **Flexibilidad** | Total | Menor (versiones de Terraform soportadas) |
| **Error típico** | Bucket sin versionado | Variables sensibles visibles |

## La receta ModaLima
| Necesidad | Pieza | Por qué |
|---|---|---|
| Estado de todos los componentes | Bucket `tfstate-modalima` versionado con CMK y prefijos por entorno | Seguridad y recuperación |
| Diez microservicios iguales | Módulo `microservicio` versionado | Consistencia |
| Prod y no-prod | Carpetas y estados separados, misma versión de módulo | Promoción controlada |
| Aplicar | Runners en OCI con instance principal, uno por entorno | Sin llaves |
| Revisión | `plan` adjunto al PR y `apply` del plan guardado | Lo revisado es lo aplicado |

## Orden recomendado de adopción
1. Estado semilla y bucket del estado como código.
2. Módulos con interfaz pequeña y versionados.
3. Composiciones por entorno y componente.
4. Runners con identidad por entorno.
5. Controles en PR (`fmt`, `validate`, `tflint`, seguridad, `plan`).
6. Detección de drift periódica.

## Reglas transversales
- El estado es un secreto.
- Versiones fijadas: módulos, providers y Terraform/OpenTofu.
- Nadie aplica prod desde su laptop.
- `moved`/`import`/`removed` en vez de editar el estado.
- Toda excepción manual se lleva al código o se revierte.

## Java en Terraform: qué construye cada `uso-en-java.md`
| Unidad | Qué construyes | Patrón común |
|---|---|---|
| Estado remoto | Auditor de solo lectura del bucket del estado | Nunca leer el contenido |
| Módulos y entornos | Comparador de stacks prod/no-prod | Lista de diferencias permitidas |
| Autenticación | Vigilante de rotación de API keys | Reloj inyectable |

## Cómo se relaciona con otros capítulos
- [IAM](../02-iam/README.md): grupos dinámicos y políticas de runners.
- [Secretos](../03-secretos/README.md): contraseñas fuera del estado.
- [Storage](../06-storage/README.md): bucket del estado.
- [Gobierno](../09-gobierno/README.md): etiquetas y cuotas aplicadas por módulos.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos, troubleshooting, repaso y prompt de NotebookLM.
