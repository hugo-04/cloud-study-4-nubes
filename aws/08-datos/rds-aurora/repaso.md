# AWS · RDS y Aurora · Repaso

## Preguntas
1. ¿Qué diferencia hay entre RDS y Aurora?
   - *RDS administra motores tradicionales sobre discos por instancia; Aurora separa cómputo y almacenamiento compartido en tres zonas, con más lectores y failover rápido.*
2. ¿Qué endpoint usas para escribir y cuál para leer?
   - *Clúster (escritor) y lector; nunca el de una instancia concreta.*
3. ¿Qué hace un failover y qué debe hacer la aplicación?
   - *Promueve un lector; la app debe reconectar al endpoint de clúster y reintentar la transacción completa.*
4. ¿Cómo se dimensiona un pool de conexiones?
   - *instancias de la app × tamaño del pool ≤ ~80 % de `max_connections`, menos conexiones reservadas.*
5. ¿Para qué sirve RDS Proxy?
   - *Reutilizar conexiones (Lambda, muchas réplicas) y suavizar failovers.*
6. ¿Qué es PITR y qué crea al restaurar?
   - *Restaurar a un segundo concreto; crea un clúster nuevo.*
7. ¿Qué ventajas tiene la autenticación IAM?
   - *Sin contraseña guardada; token de 15 minutos; control por rol.*
8. ¿Cuándo usar Aurora Serverless v2?
   - *Cargas variables o entornos de desarrollo; paga por capacidad usada.*
9. ¿Qué es Blue/Green y cuándo se usa?
   - *Entorno paralelo sincronizado para actualizar versiones o parámetros con un corte mínimo.*
10. ¿Cuándo NO usar una base relacional?
    - *Clave-valor masivo (DynamoDB), caché (ElastiCache), colas (mensajería), archivos (S3).*

## Ejercicios
1. Calcula el tamaño de pool para 12 pods y una base con `max_connections=500` y 20 reservadas.
2. Crea el clúster del ejemplo, ensaya `failover-db-cluster` y mide cuánto tarda tu aplicación en recuperarse.
3. Restaura a un punto en el tiempo a un clúster nuevo y compara una tabla.
4. Crea un usuario con IAM y conéctate con un token desde `psql`.

## Autoevaluación
- [ ] Distingo endpoints de clúster, lector e instancia.
- [ ] Calculo pools y sé cuándo poner RDS Proxy.
- [ ] Reintento transacciones completas ante errores transitorios.
- [ ] Sé restaurar con PITR y qué crea.
- [ ] Elijo entre RDS/Aurora, DynamoDB y ElastiCache con criterios.
