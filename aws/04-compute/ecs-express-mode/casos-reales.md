# AWS · ECS Express Mode · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. El prototipo que salió a producción en una tarde
**Qué pasó:** Café Andino necesitaba la API de pedidos del club de suscripción para el lunes y no tenía equipo de plataforma. **Solución:** imagen + tres roles + una llamada; HTTPS y escalado salieron de fábrica. **Lección:** para arrancar, lo simple gana; la carta completa queda disponible después.

## 2. El servicio que quedó en una VPC pública sin querer
**Qué pasó:** sin indicar subredes, el servicio usó la VPC por defecto y quedó expuesto a Internet. **Solución:** subredes privadas explícitas (ALB interno) y revisión de los *security groups*. **Lección:** lo que no declaras, lo decide el valor por defecto.

## 3. Puerto 80 y health check en `/`
**Qué pasó:** la app de Spring escuchaba en 8080 y `/` devolvía 404; las tareas se reemplazaban en bucle. **Solución:** `containerPort = 8080` y `health_check_path = /actuator/health/readiness`. **Lección:** adapta los valores por defecto a tu aplicación.

## 4. El rol de tarea que no existía
**Qué pasó:** el pipeline falló al crear el servicio porque el rol de tarea se creaba en otro stack, después. **Solución:** ordenar la dependencia: roles primero. **Lección:** el rol de tarea debe existir antes de crear o actualizar.

## 5. Dieciséis servicios, un balanceador
**Qué pasó:** cada servicio tenía su propio ALB (mucho costo) en la plataforma anterior. **Solución:** Express Mode comparte el ALB hasta 25 servicios por VPC. **Lección:** el costo fijo del balanceador se reparte.

## 6. Cuando se quedó corto
**Qué pasó:** se necesitó despliegue azul/verde propio y una regla de WAF específica. **Solución:** migrar a ECS Fargate con la misma imagen, módulos propios y el balanceador gestionado por Terraform. **Lección:** Express Mode es un excelente punto de partida, no un callejón sin salida si lo planeas.

| Problema | Solución |
|---|---|
| Salir rápido sin plataforma | Express Mode |
| Exposición accidental | Subredes privadas explícitas |
| Tareas en bucle | Puerto y health check propios |
| Falla por rol inexistente | Orden de dependencias |
| Muchos ALB | ALB compartido |
| Necesidades avanzadas | Migrar a ECS Fargate |
