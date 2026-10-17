# AWS · ECS Fargate · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. El despliegue que nunca terminaba
**Qué pasó:** una versión nueva fallaba al arrancar y ECS la reintentaba sin parar, mientras la vieja seguía sirviendo a medias. **Solución:** *circuit breaker* con *rollback* y *health check* de readiness. **Lección:** un despliegue debe poder fallar rápido y volver solo.

## 2. Tareas que mueren antes de arrancar
**Qué pasó:** el servicio mataba tareas cada minuto; Spring tardaba 70 s en iniciar y el ALB las daba por muertas. **Solución:** `health_check_grace_period_seconds = 120`. **Lección:** el arranque de Java se mide y se respeta.

## 3. `CannotPullContainerError`
**Qué pasó:** en una subred privada sin NAT, la tarea no podía bajar la imagen. **Solución:** endpoints de VPC para `ecr.api`, `ecr.dkr`, `s3` (gateway) y `logs`. **Lección:** las tareas privadas necesitan un camino hacia ECR y logs.

## 4. Spot que ahorró 60 % (y un susto)
**Qué pasó:** todo el servicio en Spot; una interrupción masiva tumbó las tres copias a la vez. **Solución:** estrategia mixta: `base = 1` en `FARGATE` y el resto en Spot. **Lección:** Spot para el exceso, no para el mínimo.

## 5. Requests cortadas en cada despliegue
**Qué pasó:** los clientes recibían 502 al desplegar. **Solución:** `server.shutdown=graceful`, `stopTimeout = 60`, `deregistration_delay` alineado. **Lección:** apagar bien es parte del despliegue.

## 6. La migración que corría en cada réplica
**Qué pasó:** Flyway al arrancar se ejecutaba en las tres réplicas a la vez. **Solución:** una tarea única (`RunTask`) antes del despliegue, desde el pipeline. **Lección:** lo que debe ocurrir una vez no va en el arranque de N réplicas.

| Problema | Solución |
|---|---|
| Despliegue atascado | Circuit breaker + rollback |
| Muerte durante el arranque | Grace period |
| No baja la imagen | Endpoints ECR/S3/logs |
| Spot tumba todo | Base en Fargate normal |
| 502 al desplegar | Graceful shutdown |
| Migración duplicada | RunTask único |
