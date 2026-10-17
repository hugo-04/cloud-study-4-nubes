# AWS · ECS Express Mode · Troubleshooting

Orden: **¿se creó el servicio? (`status` del servicio y `statusReason`) → ¿roles correctos (infraestructura, ejecución, tarea)? → ¿la tarea arranca? (eventos, `stoppedReason`) → ¿puerto y health check? → ¿red (subredes, NAT, endpoints)? → ¿límites del ALB compartido?**

| Síntoma | Causa probable | Cómo comprobarlo | Solución |
|---|---|---|---|
| Falla la creación con `AccessDenied` / rol | El pipeline no puede pasar los roles | Mensaje del error | `iam:PassRole` sobre infraestructura, ejecución y tarea |
| `InvalidParameter` por el rol de tarea | El rol no existe todavía | IAM | Crear el rol antes |
| El rol de infraestructura no puede crear recursos | Falta la política administrada o la confianza con `ecs.amazonaws.com` | Rol | Adjuntar `AmazonECSInfrastructureRoleforExpressGatewayServices` |
| Tareas en bucle, 502/503 | Puerto o health check no coinciden con la app | Target group, logs | `containerPort` y `health_check_path` correctos |
| `CannotPullContainerError` | Subredes privadas sin NAT/endpoints | `stoppedReason` | NAT o endpoints ECR/S3/logs ([Red](../../01-red/vpc-endpoints-privatelink/README.md)) |
| Servicio accesible desde Internet sin quererlo | Subredes públicas por defecto | `ingressPaths` | Subredes privadas explícitas |
| No se crea más servicios en la VPC | Límite de 25 por ALB o subredes en AZ no soportadas por el ALB | Mensaje del error | Subredes de todas las AZ; otra VPC |
| No puedo cambiar nombre, clúster o etiquetas | Son inmutables | Doc | Recrear el servicio |
| Despliegue se detiene o revierte | La alarma de despliegue defectuoso se activó | Alarma de CloudWatch, logs | Corregir la aplicación |
| El dominio propio no responde | Falta la regla de host o el certificado en el listener | Listener del ALB | Añadir regla y certificado |
| Quiero escala a cero | No disponible | — | Lambda o ECS con otra estrategia |
| Cambié el nombre del contenedor y falló la actualización | El nombre por defecto «Main» se espera | Doc | Mantener el nombre o usar task definition propia |
