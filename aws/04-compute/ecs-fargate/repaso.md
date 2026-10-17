# AWS · ECS Fargate · Repaso

## Preguntas
1. ¿Qué diferencia hay entre ECS y Fargate?
   - *ECS orquesta; Fargate es la capacidad sin servidores donde corren las tareas.*
2. ¿Task definition, task y service?
   - *Receta versionada, una ejecución, y N ejecuciones vigiladas.*
3. ¿Execution role vs task role?
   - *El primero arranca la tarea (ECR, logs, secretos); el segundo lo usa tu código.*
4. ¿Qué hace el circuit breaker?
   - *Detecta un despliegue que no se estabiliza y lo revierte.*
5. ¿Por qué `base = 1` en FARGATE y el resto en SPOT?
   - *Spot puede interrumpirse; el mínimo debe ser estable.*
6. ¿Qué pasa al recibir SIGTERM?
   - *La app cierra ordenadamente hasta `stopTimeout`; luego SIGKILL.*
7. ¿Cuándo se leen los secretos inyectados?
   - *Una sola vez, al iniciar la tarea.*
8. ¿Qué es `awsvpc`?
   - *Cada tarea con su ENI, IP privada y security groups.*
9. ¿Cómo corres una migración una sola vez?
   - *`RunTask` desde el pipeline antes del despliegue.*
10. ¿Cuándo elegir EKS en vez de ECS?
    - *Cuando necesitas el ecosistema y las APIs de Kubernetes.*

## Ejercicios
1. Calcula CPU/memoria para una app Spring con 512 MB de heap y define el `MaxRAMPercentage`.
2. Escribe la política `iam:PassRole` del pipeline con condición.
3. Diseña la estrategia de capacity providers para un servicio con mínimo 2 tareas y picos de 10.
4. Describe qué endpoints necesita una tarea en subred privada.

## Autoevaluación
- [ ] Distingo los dos roles.
- [ ] Sé configurar despliegue seguro (circuit breaker, grace period, graceful shutdown).
- [ ] Sé diagnosticar un `stoppedReason`.
- [ ] Sé qué necesita una tarea privada para arrancar.
