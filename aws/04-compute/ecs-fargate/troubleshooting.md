# AWS · ECS Fargate · Troubleshooting

Orden: **¿la tarea arranca? (eventos del servicio, `stoppedReason`) → ¿baja la imagen? → ¿pasa el health check? → ¿red y SG? → ¿permisos (execution role vs task role)? → ¿recursos (OOM)?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| `CannotPullContainerError` | Sin ruta a ECR, imagen/etiqueta inexistente, falta permiso del execution role | `describe-tasks` → `stoppedReason`; rutas de la subred | Endpoints ECR+S3 o NAT; revisar etiqueta y permisos |
| `ResourceInitializationError: unable to pull secrets` | Execution role sin permiso al secreto/KMS, o sin endpoint a `secretsmanager`/`ssm` | `stoppedReason` | Permiso al secreto y a la clave; endpoint |
| Tareas mueren en bucle, `Task failed ELB health checks` | Ruta/puerto del health check mal, arranque lento | Target group → salud; logs | Corregir ruta/puerto; subir `health_check_grace_period_seconds` |
| `OutOfMemoryError: Container killed` (exit 137) | Memoria de la tarea menor que la JVM necesita | `exitCode`, métricas de memoria | Subir memoria; `-XX:MaxRAMPercentage=75` |
| Despliegue en `IN_PROGRESS` eternamente | Tareas nuevas no pasan health check; sin circuit breaker | Eventos del servicio | Activar circuit breaker; corregir |
| `AccessDeniedException` desde el código | Falta permiso en el **task role** (no en el de ejecución) | Logs; qué rol usa el SDK | Añadir permiso al task role |
| `iam:PassRole` denegado al desplegar | El pipeline no puede pasar esos roles | Error del pipeline | Permitir `PassRole` sobre los dos roles con condición del servicio |
| 502/504 desde el balanceador | Tarea caída, SG no permite al ALB, timeout | Target group, SG | SG de la tarea desde el SG del ALB; timeouts |
| `RESOURCE:ENI` o sin IP | Subred sin IPs libres | IPs disponibles de la subred | Subredes más grandes ([Red](../../01-red/vpc-subredes/README.md)) |
| ECS Exec no abre sesión | Falta `enable_execute_command`, permisos SSM del task role o endpoint `ssmmessages` | `aws ecs execute-command` | Activar, permisos y endpoint |
| Terraform revierte el número de tareas | Autoescalado vs `desired_count` | `plan` | `ignore_changes = [desired_count]` |
| Sin logs | Grupo de logs inexistente o sin permiso | Execution role | Crear grupo; permisos `logs:*` mínimos |
