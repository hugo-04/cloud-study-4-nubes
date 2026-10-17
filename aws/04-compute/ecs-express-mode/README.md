# AWS · Compute · Amazon ECS Express Mode

**ECS Express Mode** es la forma más corta de poner un contenedor en producción en AWS: entregas **una imagen y dos roles de IAM** y ECS crea por ti el servicio en Fargate, el balanceador, los certificados, el autoescalado, los grupos de seguridad y los logs. Es el reemplazo recomendado por AWS para quienes buscaban la simplicidad de App Runner (que **ya no admite clientes nuevos**).

## 1. Qué es

**Analogía:** el **menú del día** frente a la carta. En vez de elegir cada plato (balanceador, red, escalado, certificados), pides «el menú»: una imagen y dos roles. La cocina (ECS) arma todo con buenas prácticas. Si algún día quieres cocinar a tu manera, el mismo restaurante tiene la carta completa ([ECS Fargate](../ecs-fargate/README.md)).

```
 Tú entregas:  imagen + rol de ejecución + rol de infraestructura (+ rol de tarea opcional)
                           │   1 llamada a la API
                           ▼
 ECS crea:  cluster "default" · task definition · servicio Fargate (despliegue canary)
            ALB con HTTPS + certificado ACM · reglas y target groups · security groups
            auto scaling (CPU 60 %, 1–20 tareas) · log group · alarma de despliegues defectuosos
```

## 2. Cómo funciona por dentro

| Pieza | Qué hace |
|---|---|
| **Rol de infraestructura** | Permite a ECS crear y gestionar por ti los recursos (balanceador, certificados, escalado). Política administrada `AmazonECSInfrastructureRoleforExpressGatewayServices` |
| **Rol de ejecución** | Igual que en ECS: bajar la imagen, escribir logs, leer secretos inyectados |
| **Rol de tarea (opcional)** | Permisos del código de tu aplicación; **debe existir antes** de crear o actualizar el servicio |
| **Contenedor principal** | Imagen, puerto, comando, variables, secretos, credenciales de repositorio privado, configuración de logs |
| **ALB compartido** | Hasta **25 servicios Express de la misma VPC** comparten un balanceador (ahorro de costo); ECS agrega o retira balanceadores según haga falta |
| **Despliegues canary** | Cada cambio crea una revisión que recibe tráfico gradualmente; la estrategia **no se puede cambiar**; una alarma detecta despliegues defectuosos |
| **Autoescalado** | Por defecto 1 a 20 tareas con objetivo de 60 % de CPU; también por memoria o peticiones por tarea |
| **Red** | Sin subredes indicadas usa las **subredes públicas de la VPC por defecto**; con subredes **privadas** crea un ALB **interno** (sin IP pública) y necesitas NAT para salir a Internet |

### Valores por defecto (verifica los vigentes)
CPU 1024 (1 vCPU) · memoria 2048 MB · arquitectura `X86_64` (puedes elegir `ARM64`) · puerto 80 · *health check* en `/` · nombre de contenedor «Main» (cambiarlo puede romper actualizaciones posteriores).

### Lo que NO se puede cambiar después
Nombre del servicio, clúster, **configuración del balanceador**, **estrategia de despliegue** y **etiquetas** (solo se añaden al crear). Si necesitas control total, usa una definición de tarea propia (`taskDefinitionArn`) o pasa a [ECS Fargate](../ecs-fargate/README.md).

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Una API o web en contenedor, equipo pequeño, quieres URL HTTPS y escalado ya | **Express Mode** |
| Prototipos y servicios internos con buenas prácticas por defecto | **Express Mode** |
| Plataforma con módulos propios de red, balanceadores y despliegues azul/verde | [ECS Fargate](../ecs-fargate/README.md) |
| Necesitas Kubernetes | [EKS](../eks/README.md) |
| Cargas por eventos | [Lambda](../lambda/README.md) |
| Cero réplicas cuando no hay tráfico (escala a cero) | **No**: el mínimo es 1 tarea |
| Consumidores de colas sin HTTP | ECS Fargate (Express Mode es para servicios con entrada HTTP) |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Express Gateway Service** | El servicio que crea Express Mode |
| **Infrastructure role** | El permiso para que ECS arme la infraestructura por ti |
| **ALB compartido** | Un balanceador usado por varios servicios de la VPC |
| **Canary** | Despliegue gradual con una pequeña porción de tráfico primero |
| **Ingress path** | Endpoint por el que se llega al servicio |
| **Primary container** | El contenedor principal de la tarea |
| **Task definition propia** | Escapatoria para tener control total manteniendo Express |

## 5. Cómo se usa
1. Sube la imagen a ECR y crea los roles (ejecución, infraestructura y, si hace falta, tarea).
2. Crea el servicio: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf) o la CLI [`ejemplos/cli/express.sh`](ejemplos/cli/express.sh).
3. Obtén el endpoint con `describe-express-gateway-service` (campo `ingressPaths`).
4. Cada cambio de imagen es una actualización con despliegue canary.
5. Dominio propio: añade una regla de host y el certificado en el listener HTTPS del ALB (verifica el procedimiento vigente).
6. Si superas las limitaciones, migra a ECS Fargate con la misma imagen.

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **Pipeline** | `ecs:CreateExpressGatewayService/Update/Delete`, `iam:PassRole` sobre los **tres** roles | — |
| **Rol de infraestructura** | Crea ALB, grupos de seguridad, certificados, escalado | — |
| **Rol de ejecución** | — | Imagen, logs, secretos inyectados |
| **Rol de tarea** | — | Lo que el código necesite (mínimo privilegio) |

- Con subredes privadas, el ALB es **interno**: bueno para servicios internos; para exponer a Internet necesitas subredes públicas.
- El *security group* de la tarea solo admite al balanceador; los que añadas generan rutas de entrada extra: **revísalos**.
- `iam:PassRole` con condición `iam:PassedToService = ecs.amazonaws.com` / `ecs-tasks.amazonaws.com` según el rol.
- Secretos por `secrets` (Secrets Manager / Parameter Store), nunca en `environment`.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Indicar **subredes y security groups** explícitos | Dejar que use la VPC por defecto en producción sin saberlo |
| `containerPort` y `health_check_path` propios (`/actuator/health/readiness`) | Dejar puerto 80 y `/` si tu app no los usa |
| Crear primero el rol de tarea | Referenciar un rol de tarea inexistente |
| Etiquetar al crear (no se pueden añadir después) | Olvidar las etiquetas de costo |
| Un servicio por equipo/entorno aprovechando el ALB compartido | Mezclar entornos distintos en la misma VPC sin pensar |
| Documentar la salida (migrar a ECS Fargate) | Asumir que cubre cualquier necesidad futura |
| Ajustar CPU/memoria/ARM64 según medición | Dejar 1 vCPU / 2 GB «porque sí» |

## 8. Límites, costos y versiones
- **Costo:** Express Mode no cobra por sí mismo; pagas los recursos subyacentes (Fargate, ALB —compartido—, NAT, logs). *Verifica precios.*
- **Límites:** 25 servicios por ALB compartido; sin escala a cero; ciertos campos inmutables.
- **Disponibilidad:** funciones relativamente nuevas; revisa regiones y cambios en la documentación.
- **Terraform:** recurso `aws_ecs_express_gateway_service`. Validado con `init` + `validate`.
- **App Runner:** AWS lo mantiene para clientes existentes (sin funciones nuevas) y ya **no está abierto a clientes nuevos**.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
