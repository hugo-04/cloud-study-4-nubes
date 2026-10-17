# AWS · ECS Express Mode · Repaso

## Preguntas
1. ¿Qué entregas para crear un servicio Express?
   - *Una imagen y los roles de ejecución e infraestructura (y de tarea si la app lo necesita).*
2. ¿Qué crea ECS por ti?
   - *Servicio Fargate, ALB con HTTPS y certificado, security groups, autoescalado, logs y alarma.*
3. ¿Por qué cuidar las subredes?
   - *Sin indicarlas usa la VPC por defecto con subredes públicas.*
4. ¿Qué es el ALB compartido?
   - *Un balanceador usado por hasta 25 servicios de la misma VPC.*
5. ¿Qué estrategia de despliegue usa?
   - *Canary, y no se puede cambiar.*
6. ¿Qué es inmutable tras crear el servicio?
   - *Nombre, clúster, balanceador, estrategia y etiquetas.*
7. ¿Cuándo pasar a ECS Fargate?
   - *Si necesitas control de balanceador, despliegue azul/verde, WAF propio o escala a cero (que Express no tiene).*
8. ¿Qué rol debe existir antes de crear el servicio?
   - *El rol de tarea, si lo usas.*
9. ¿Qué pasó con App Runner?
   - *Ya no admite clientes nuevos; AWS recomienda Express Mode.*
10. ¿Qué valores por defecto debes cambiar casi siempre?
    - *Puerto, health check, CPU/memoria y las subredes.*

## Ejercicios
1. Escribe la llamada de creación para una app Spring en el puerto 8080 con subredes privadas.
2. Lista los permisos `iam:PassRole` del pipeline.
3. Define los criterios para decidir entre Express Mode y ECS Fargate en tu empresa.
4. Planea la migración de un servicio Express a ECS Fargate sin cortar tráfico.

## Autoevaluación
- [ ] Sé qué crea y qué no puede cambiar Express Mode.
- [ ] Sé configurar red, puerto y health check.
- [ ] Sé decidir cuándo pasar a ECS Fargate.
- [ ] Sé qué cambió con App Runner.
