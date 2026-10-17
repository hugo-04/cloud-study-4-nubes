# AWS · 04 Compute

Dónde corre el código de tus microservicios. AWS ofrece varias opciones; la clave es elegir **cuánto quieres administrar** frente a **cuánto control necesitas**.

| Servicio | La pregunta que responde | Analogía | La eliges para |
|---|---|---|---|
| [ECS Fargate](ecs-fargate/README.md) | ¿Cómo corro contenedores **sin administrar servidores**? | Restaurante con cocina alquilada por minuto | Microservicios HTTP y consumidores de colas, jobs; el punto medio más usado |
| [ECS Express Mode](ecs-express-mode/README.md) | ¿Cómo pongo **una imagen en producción con una llamada**? | El menú del día | APIs y webs de equipos pequeños, prototipos, servicios internos |
| [EKS](eks/README.md) | ¿Cómo uso **Kubernetes** sin operar su plano de control? | Un aeropuerto: AWS opera la torre | Muchos servicios, ecosistema Kubernetes (Helm, operadores, malla) |
| [Lambda](lambda/README.md) | ¿Cómo ejecuto código **solo cuando hay un evento**? | Un taxi por viaje | Colas, eventos de S3, tareas programadas, APIs de tráfico irregular |

> Nota: **AWS App Runner ya no admite clientes nuevos** (los existentes siguen funcionando, sin funciones nuevas); AWS recomienda [ECS Express Mode](ecs-express-mode/README.md) para esa necesidad.

## Árbol de decisión: «quiero…»

```
¿Reacciono a un evento (cola, archivo subido, cron) y el trabajo dura < 15 min?
   └─ Lambda (con SnapStart si es Java)

¿Quiero una API en contenedor con HTTPS y escalado YA, con el mínimo de decisiones?
   └─ ECS Express Mode

¿Quiero contenedores sin servidores pero con control de red, balanceador y despliegues?
   └─ ECS Fargate

¿Mi equipo ya trabaja con Kubernetes (Helm, operadores, malla) o lo necesita?
   └─ EKS (con Auto Mode si quieres menos operación)

¿Necesito escala a cero real?
   └─ Lambda (Express Mode y Fargate mantienen al menos 1 tarea)

¿Proceso de más de 15 minutos o conexiones largas (WebSocket, gRPC en flujo)?
   └─ ECS Fargate o EKS

¿Necesito GPU, kernel especial o contenedores privilegiados?
   └─ ECS sobre EC2 o EKS con nodos EC2
```

## Comparativa

| Característica | Lambda | ECS Express Mode | ECS Fargate | EKS |
|---|---|---|---|---|
| **Unidad** | Función | Servicio (contenedor) | Servicio (contenedor) | Pod |
| **Administras** | Código | Imagen + roles | Imagen, red, balanceador, escalado | Clúster, add-ons, nodos (salvo Auto Mode) |
| **Escala a cero** | **Sí** | No (mín. 1) | No (mín. 1 recomendado) | Con Karpenter/KEDA, con matices |
| **Arranque** | Frío (mitigable con SnapStart) | Tarea nueva (~minuto) | Tarea nueva (~minuto) | Pod nuevo (segundos si hay nodo) |
| **Duración máxima** | 15 min | Ilimitada | Ilimitada | Ilimitada |
| **Entrada HTTP** | API Gateway / ALB / Function URL | **Incluida** (ALB + HTTPS) | Tú configuras ALB | Ingress / controlador |
| **Despliegue** | Versiones y alias | Canary (fijo) | Rolling / blue-green (eliges) | Rolling, canary con herramientas |
| **Curva de aprendizaje** | Baja | **Muy baja** | Media | Alta |
| **Portabilidad** | Baja | Contenedor estándar | Contenedor estándar | **Alta** (Kubernetes) |
| **Costo fijo** | Ninguno | Tareas + ALB compartido | Tareas + ALB | Clúster + nodos + ALB |
| **Error típico** | Cold start y reintentos sin idempotencia | Red por defecto pública | Roles mezclados, sin graceful shutdown | IPs agotadas, upgrades tardíos |

*(Precios y cuotas: verifica en la documentación oficial.)*

## La receta ModaLima

| Carga | Dónde corre | Por qué |
|---|---|---|
| API de Pedidos y de Catálogo | **ECS Fargate** (mín. 2 tareas, Spot para el exceso) | Tráfico estable, control de red y despliegue |
| Consumidor de pagos confirmados | **Lambda** con SQS, fallos parciales y SnapStart | Picos irregulares, pago por uso |
| Panel interno de logística | **ECS Express Mode** | Equipo pequeño, HTTPS y escalado ya |
| Plataforma de datos con operadores y malla | **EKS** | Ecosistema Kubernetes |
| Generación de informes nocturnos | **ECS Fargate** `RunTask` programado | Más de 15 min |

## Orden recomendado de adopción
1. **Empieza simple:** Express Mode o Lambda para lo nuevo; **Fargate** para el servicio central.
2. **Imágenes en ECR** con escaneo y etiquetas inmutables; **un rol por servicio**.
3. **Probes y apagado ordenado** en cada aplicación Java antes de escalar.
4. **Autoescalado** con métricas reales; Spot para el exceso.
5. **EKS solo con una razón** (equipo, ecosistema, portabilidad) y un plan de actualizaciones.
6. **Todo como código** (capítulo 10).

## Reglas transversales
- **Dos identidades distintas:** la que *arranca* la carga (ejecución) y la que usa *tu código* (tarea/pod/función). Nunca una sola con todo.
- **Subredes privadas** para el cómputo; salida por NAT o endpoints ([Red](../01-red/vpc-endpoints-privatelink/README.md)).
- **Apagado ordenado** (SIGTERM → terminar en curso → salir) y **probes de readiness** con arranque lento de Java contemplado.
- **JVM consciente del contenedor:** `MaxRAMPercentage` + `ExitOnOutOfMemoryError`.
- **Idempotencia** en todo lo que reintenta (colas, Lambda, despliegues).
- **Imagen por digest**, no `latest`.
- **Mide antes de dimensionar** (CPU/memoria/concurrencia).

## Java: qué hace cada `uso-en-java.md`

| Servicio | Qué construyes desde Java | Patrón común |
|---|---|---|
| ECS Fargate | Metadatos de la tarea, diagnóstico del servicio, `RunTask` para migraciones, redespliegue | SDK + función pura de diagnóstico |
| ECS Express Mode | Validación de la especificación y alta/consulta/baja de servicios | Validador puro + SDK |
| EKS | Auditoría del clúster (versión, nodos, add-ons) e identidad del pod | Reglas puras + SDK |
| Lambda | Handler con fallos parciales, idempotencia, lote concurrente (Reactor/Mutiny), SnapStart | Núcleo puro + handler de Java puro, Spring Cloud Function o Quarkus |

Reglas comunes: **un cliente SDK por aplicación**, **funciones puras** para las reglas, y en reactivo todo lo bloqueante va a `boundedElastic` / pool de trabajadores.

## Cómo se relacionan con otros capítulos
- [Red](../01-red/README.md): subredes, security groups y endpoints que necesita el cómputo.
- [IAM](../02-iam/README.md): roles de tarea/pod/función y `iam:PassRole`; Pod Identity e IRSA en EKS.
- [Secretos](../03-secretos/README.md): inyección de secretos y parámetros en ECS, EKS y Lambda.
- [Ingress y API](../05-ingress-api/README.md): ALB, API Gateway y CloudFront delante de este cómputo.
- [Mensajería](../07-mensajeria/README.md): SQS, SNS y Kafka como origen de eventos.
- [Terraform en AWS](../10-terraform/README.md): todo esto como código y pipelines.

Cada carpeta trae: teoría, casos reales, uso desde Java (Spring MVC/WebFlux y Quarkus imperativo/reactivo), ejemplos (CLI, Terraform, JSON/YAML), troubleshooting, repaso y prompt de NotebookLM.
