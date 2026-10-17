# AWS · Compute · Amazon ECS con Fargate

**Amazon ECS** es el orquestador de contenedores propio de AWS; **Fargate** es la forma de ejecutarlos **sin administrar servidores**. Tú describes el contenedor y cuánta CPU/memoria necesita; AWS pone la capacidad, la parchea y la cobra por segundo.

## 1. Qué es

**Analogía:** un restaurante donde tú escribes la **receta** (task definition), decides cuántos **cocineros iguales** quieres trabajando (service) y el gerente (ECS) reemplaza al que se enferma. Con Fargate no compras la cocina: la alquilas por minuto y nunca ves la instalación eléctrica.

```
 Cluster (agrupación lógica)
 └─ Service "pedidos" (quiero 3 copias, detrás de un ALB)
     ├─ Task #1 ── ENI propia (IP privada) ── contenedor app (+ sidecars)
     ├─ Task #2
     └─ Task #3
 Task definition "pedidos:42"  ← receta inmutable (imagen, CPU, memoria, variables, roles)
```

## 2. Cómo funciona por dentro

| Pieza | Qué es |
|---|---|
| **Cluster** | Agrupación lógica de servicios y tareas. En Fargate no tiene servidores que administrar |
| **Task definition** | Plantilla **versionada e inmutable** (`familia:revisión`): contenedores, imagen, CPU/memoria, puertos, variables, secretos, logs, roles, volúmenes |
| **Task** | Una instancia en ejecución de la definición (uno o varios contenedores que comparten red y ciclo de vida) |
| **Service** | Mantiene N tareas vivas, las reemplaza, las registra en el balanceador y gestiona los despliegues |
| **Capacity provider** | De dónde sale la capacidad: `FARGATE` o `FARGATE_SPOT` (más barata, puede interrumpirse con aviso de 2 minutos) |
| **Red `awsvpc`** | Cada tarea recibe su **propia interfaz de red** (IP privada de tu subred) y sus propios *security groups* |
| **Execution role** | Rol que usa **ECS/Fargate** para arrancar la tarea: bajar la imagen de ECR, escribir logs, leer los secretos que inyecta |
| **Task role** | Rol que usa **tu código** (el SDK dentro del contenedor) para llamar a S3, SQS, DynamoDB… |
| **Service Connect / Cloud Map** | Descubrimiento y comunicación entre servicios por nombre |
| **ECS Exec** | Shell dentro de un contenedor en ejecución vía SSM (sin abrir puertos) |

### Tamaños (CPU/memoria)
Se eligen **combinaciones permitidas**: p. ej. 0,25 vCPU con 0,5–2 GB; 1 vCPU con 2–8 GB; 4 vCPU con 8–30 GB… (verifica la tabla vigente). Opciones: arquitectura `X86_64` o **`ARM64` (Graviton)**, normalmente más barata; almacenamiento efímero de 20 GiB ampliable (verifica el máximo).

### Despliegues
| Estrategia | Cómo funciona |
|---|---|
| **Rolling (ECS)** | Lanza tareas nuevas y retira las viejas según `minimumHealthyPercent` / `maximumPercent` |
| **Circuit breaker** | Si las tareas nuevas no se estabilizan, **detiene y revierte** al despliegue anterior |
| **Blue/green** | Dos conjuntos de tareas y cambio de tráfico en el balanceador (nativo de ECS o con CodeDeploy; verifica la opción vigente) |

### Qué pasa al apagar una tarea
ECS envía **SIGTERM**, espera `stopTimeout` (por defecto 30 s, máximo 120 s) y luego **SIGKILL**. La aplicación debe terminar las peticiones en curso (*graceful shutdown*), y el balanceador debe dejar de enviarle tráfico (`deregistration_delay`).

### Autoescalado
**Application Auto Scaling** ajusta el `desiredCount` del servicio: *target tracking* sobre CPU, memoria o peticiones por tarea del ALB; también por calendario.

### Secretos y configuración
En la definición, `secrets: [{name, valueFrom}]` toma el valor de **Secrets Manager** o **Parameter Store** al arrancar la tarea y lo entrega como variable de entorno. Ojo: **se lee una vez al iniciar**; si el secreto rota, hay que reiniciar la tarea o leerlo desde el código ([Secrets Manager](../../03-secretos/secrets-manager/README.md)).

## 3. Para qué sirve y cuándo NO

| Situación | Decisión |
|---|---|
| Microservicios HTTP o consumidores de colas, sin querer administrar nodos | **ECS Fargate** |
| Procesos por lotes y tareas únicas (migraciones, jobs) | **ECS Fargate** con `RunTask` |
| Quieres lo más simple posible: imagen → URL pública | [ECS Express Mode](../ecs-express-mode/README.md) |
| Necesitas el ecosistema Kubernetes (operadores, Helm, malla) | [EKS](../eks/README.md) |
| Eventos cortos, picos impredecibles, pago por invocación | [Lambda](../lambda/README.md) |
| Necesitas GPU, kernel especial o contenedores privilegiados | ECS sobre EC2 (no Fargate) |
| Carga estable las 24 h y muy intensiva | Comparar con EC2 + Savings Plans |

## 4. Conceptos clave

| Término | En simple |
|---|---|
| **Task definition** | La receta versionada |
| **Task / Service** | Una ejecución / N ejecuciones vigiladas |
| **awsvpc** | Cada tarea con su propia IP y su propio firewall |
| **Execution role vs task role** | «El que arranca la tarea» vs «el que usa el código» |
| **Capacity provider** | Fargate normal o Spot |
| **Circuit breaker** | Revertir solo un despliegue malo |
| **Grace period** | Tiempo en que el balanceador no mata una tarea que aún arranca |
| **stopTimeout** | Tiempo entre SIGTERM y SIGKILL |
| **ECS Exec** | Shell remoto seguro dentro del contenedor |

## 5. Cómo se usa
1. Construye la imagen y súbela a **ECR** (escaneo activado, etiquetas inmutables).
2. Define la tarea y el servicio con Terraform: [`ejemplos/terraform/main.tf`](ejemplos/terraform/main.tf).
3. Registra el servicio en un balanceador ([Ingress y API](../../05-ingress-api/README.md)) con *health check* a `/actuator/health/readiness`.
4. Configura autoescalado y *circuit breaker*.
5. Operación diaria con la CLI: [`ejemplos/cli/ecs.sh`](ejemplos/cli/ecs.sh). Definición de contenedor de referencia: [`ejemplos/json/contenedor.json`](ejemplos/json/contenedor.json).

## 6. Seguridad

| Identidad | Plano de control | Plano de datos |
|---|---|---|
| **Pipeline de CI/CD** | `ecs:RegisterTaskDefinition`, `ecs:UpdateService`, `iam:PassRole` (solo sobre los dos roles de la tarea) | — |
| **Execution role** | — | Bajar de ECR, escribir logs, leer **solo** los secretos inyectados |
| **Task role** | — | Lo que el código necesite (mínimo privilegio) |
| **Operadores** | `ecs:Describe*`, `ecs:ExecuteCommand` (restringido y auditado) | — |

- **`iam:PassRole` con condición** `iam:PassedToService = ecs-tasks.amazonaws.com`: sin esto, un pipeline comprometido podría pasar un rol poderoso.
- Tareas en **subredes privadas**, sin IP pública; salida por NAT o endpoints ([Red](../../01-red/vpc-endpoints-privatelink/README.md): ECR, S3, logs, secretos).
- *Security group* de la tarea: entrada **solo desde el SG del balanceador**.
- Sistema de archivos raíz de solo lectura, usuario no-root, imagen mínima.

## 7. Qué hacer y qué NO hacer

| ✅ Hacer | ❌ No hacer |
|---|---|
| Dos roles separados (ejecución y tarea) | Un solo rol con todo |
| Circuit breaker + health check de *readiness* | Desplegar sin salida de emergencia |
| `FARGATE` base + `FARGATE_SPOT` para el exceso tolerante | Spot para la única copia de un servicio crítico |
| `ARM64` si tus imágenes lo soportan | Elegir CPU/memoria «a ojo» sin medir |
| Imagen por **digest** o etiqueta inmutable | `latest` en producción |
| Graceful shutdown y `stopTimeout` ajustado | Dejar que SIGKILL corte peticiones |
| `ignore_changes = [desired_count]` si hay autoescalado | Que Terraform pelee con el autoescalador |
| Logs a CloudWatch con retención | Logs sin retención (costo infinito) |

## 8. Límites, costos y versiones
- **Costo:** por vCPU-segundo y GB-segundo (mínimo 1 minuto), almacenamiento extra, NAT/transferencia, balanceador. Spot con descuento grande, con interrupciones. *Verifica precios y cuotas (tareas por servicio, tareas lanzadas por segundo).*
- **Terraform:** `aws_ecs_cluster`, `aws_ecs_task_definition`, `aws_ecs_service`, `aws_appautoscaling_*`. Validado con `init` + `validate`.

**Siguiente:** [casos reales](casos-reales.md) · [uso en Java](uso-en-java.md) · [troubleshooting](troubleshooting.md) · [repaso](repaso.md) · [NotebookLM](notebooklm.md)
