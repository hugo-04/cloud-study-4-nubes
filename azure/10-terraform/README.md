# Azure · 10 Terraform en Azure

Terraform convierte la infraestructura en **código que se revisa, se prueba y se repite**. Este capítulo reúne las tres piezas que lo hacen seguro en Azure: dónde vive su memoria, con qué identidad se ejecuta y cómo se organiza para reutilizarlo.

| Servicio | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [Estado remoto](estado-remoto/README.md) | ¿**Dónde** recuerda Terraform lo que construyó? | El libro de obra del edificio | Backend `azurerm` privado, sin claves, versionado y con bloqueo; dividir el estado; `moved`, `import`, `removed` |
| [Autenticación y pipelines](autenticacion-y-pipelines/README.md) | ¿**Quién** ejecuta los cambios y con qué permisos? | El pase de visitante de un solo día | Federación OIDC sin secretos, identidades de plan y apply, GitHub Actions y Azure DevOps, puertas de seguridad |
| [Módulos y entornos](modulos-y-entornos/README.md) | ¿**Cómo** reutilizo y organizo el código? | La receta y las cocinas | Módulos versionados y probados, un estado por entorno, migraciones sin destruir |

> Las tres **se apoyan entre sí**: el estado guarda lo que construyeron los pipelines; los pipelines solo funcionan con identidades que el estado y los módulos asumen; y los módulos son lo que los pipelines despliegan, entorno por entorno.

## Árbol de decisión: «quiero que…»

```
¿Quiero que el equipo comparta una sola memoria y no se pisen dos apply?
   └─ Estado remoto en una cuenta de almacenamiento, un estado por componente y entorno

¿Quiero que el pipeline no guarde ninguna contraseña?
   └─ Identidad administrada + credencial federada (OIDC), con subject por entorno

¿Quiero que un PR solo pueda leer y que solo producción aplique tras aprobación?
   └─ Dos identidades por entorno (plan: Reader / apply: Contributor) + entorno protegido

¿Quiero que veinte aplicaciones usen la misma receta segura?
   └─ Módulo versionado (?ref=) + for_each + pruebas con terraform test

¿Quiero renombrar o reorganizar sin destruir?
   └─ moved (y verificar «0 to destroy» en el plan)

¿Quiero adoptar lo que se creó a mano?
   └─ import + plan -generate-config-out (o aztfexport) + plan sin cambios

¿Quiero detectar cambios hechos fuera de Terraform?
   └─ plan nocturno con -detailed-exitcode y aviso (deriva)

¿Quiero impedir que un plan borre la base de datos?
   └─ Puerta automática sobre terraform show -json (jq, conftest o el analizador en Java) + bloqueo CanNotDelete

¿Quiero un portal donde los equipos pidan su aplicación?
   └─ Java valida y genera tfvars → pull request → pipeline → aprobación (el portal nunca aplica)
```

## Comparativa

| Característica | Estado remoto | Autenticación y pipelines | Módulos y entornos |
|---|---|---|---|
| **Qué resuelve** | Memoria compartida, bloqueo, recuperación | Identidad sin secretos y permisos mínimos | Reutilización, estándares y orden |
| **Dónde vive** | Blob en una cuenta de almacenamiento | Identidades administradas, credenciales federadas, roles | Carpetas y repositorios de código |
| **Si falla** | Nadie puede planificar; estado perdido | Los pipelines no entran, o entran con demasiado poder | Cambios inesperados, copias distintas por entorno |
| **Riesgo principal** | El estado contiene secretos | El `subject` demasiado amplio; *Owner* en el pipeline | Módulos sin versión; secretos en el contrato |
| **Se versiona en Git** | No (nunca) | Sí (código de identidades y pipelines) | Sí (con etiquetas) |
| **Roles de datos** | *Storage Blob Data Owner* sobre el contenedor | Los pipelines lo reciben de este capítulo | — |
| **Se prueba con** | Simulacro de recuperación | PR de prueba y deriva nocturna | `terraform test` con proveedor simulado |
| **Error típico** | `force-unlock` sin comprobar | Cancelar un apply a medias | `count` sobre listas que cambian de orden |

## La receta ModaLima (cómo se ve junto)

| Pieza | Decisión |
|---|---|
| **Estado** | Cuenta `stmodalimaprodtfstate01` (producción) y otra para no producción; contenedor `tfstate`; clave `<entorno>/<componente>.tfstate` |
| **Identidades** | `id-tf-<entorno>-plan` y `id-tf-<entorno>-apply`, con credenciales federadas por entorno de GitHub (`dev-plan`, `dev`, `prod-plan`, `prod`) |
| **Pipelines** | Plan en cada PR, apply tras fusionar a `main` (dev automático, prod con revisores), plan guardado, deriva nocturna |
| **Módulos** | `app-base` v1.x en un repositorio de módulos con etiquetas; consumidos con `?ref=` fijo; pruebas con `mock_provider` |
| **Entornos** | Un directorio por entorno (`envs/dev`, `envs/prod`) con su `tfvars` y su estado |
| **Puertas** | `fmt`, `validate`, `tflint`, `trivy`, `terraform test`, analizador del plan (borrados protegidos, roles, exposición pública), `infracost` |
| **Gobierno** | Grupos de administración, políticas, bloqueos y presupuestos del [capítulo 09](../09-gobierno/README.md) también como código |

## Orden recomendado de adopción

1. **Estado remoto** primero: cuenta privada, sin claves, con versionado y borrado suave; un estado por componente.
2. **Un entorno de laboratorio** con el pipeline completo (plan en PR, apply tras aprobar) usando OIDC.
3. **Dos identidades por entorno**, con roles mínimos y estados en contenedores separados.
4. **Extraer el primer módulo** (el que más se repite), con pruebas y una etiqueta de versión.
5. **Adoptar lo existente** con `import` y un plan sin cambios.
6. **Puertas automáticas** (escáneres y análisis del plan) y **deriva nocturna** con aviso.
7. **Gobierno como código**: jerarquía, políticas, bloqueos y presupuestos con este mismo flujo.

## Reglas transversales

- **El estado es un secreto:** privado, versionado, con roles de datos mínimos.
- **Sin secretos de larga vida:** identidades federadas; el `subject` es parte de la seguridad.
- **Plan lee, apply cambia:** dos identidades, y apply solo tras aprobación.
- **Aplica el plan que revisaste** y no canceles un apply en curso.
- **El plan debe decir «0 to destroy»** después de cualquier refactor.
- **Versiona los módulos** y adóptalos entorno por entorno.
- **Seguro por defecto** en cada módulo; abrir algo exige pedirlo.
- **Nada se cambia a mano en producción:** si ocurre, la deriva nocturna lo muestra.

## Java en Terraform: qué hace cada `uso-en-java.md`

Terraform **no tiene SDK para Java** y tu microservicio no declara infraestructura. Lo que se construye en Java es **plataforma**: vigilar, validar y revisar. Todos siguen el mismo molde: funciones puras para las reglas y un borde delgado (SDK, proceso o HTTP).

| Servicio | Qué construyes desde Java | Patrón común |
|---|---|---|
| Estado remoto | Auditor del almacén de estados: inventario, bloqueos largos, higiene de la cuenta, métricas | SDK de blobs y de almacenamiento + reglas puras + *gauges* |
| Autenticación y pipelines | Analizador de planes (`terraform show -json`) y ejecutor de procesos aislado para portales | `azure-json` + reglas puras + `ProcessBuilder` con tiempo límite |
| Módulos y entornos | Validación de solicitudes y generador determinista de `terraform.tfvars.json` | Reglas puras + salida estable + prueba de contrato contra el módulo |

Reglas comunes: **nunca registrar valores de planes ni de estados**, el servicio **observa o propone, nunca aplica**, y en reactivo todo lo bloqueante va a `boundedElastic` / pool de trabajadores / hilos virtuales.

## Cómo se relacionan con otros capítulos

- [Fundamentos](../00-fundamentos/README.md): jerarquía de Azure, suscripciones y nombres.
- [Red](../01-red/README.md): Private Endpoint y DNS privado para el almacén de estados y los ejecutores propios.
- [IAM](../02-iam/README.md): identidades administradas, RBAC y Workload Identity; los roles de los pipelines.
- [Secretos](../03-secretos/README.md): lo que Terraform lee de Key Vault en lugar de recibirlo como variable.
- [Gobierno](../09-gobierno/README.md): políticas, bloqueos y presupuestos que se despliegan con este flujo.
- Cada servicio de los demás capítulos trae su `ejemplos/terraform/`, escrito con las convenciones de este capítulo.
- Material independiente de la nube sobre Terraform: módulo `transversal/terraform` *(por escribir)*.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos (CLI, Terraform, HCL, consultas y los específicos de cada servicio), troubleshooting, repaso y prompt de NotebookLM.
