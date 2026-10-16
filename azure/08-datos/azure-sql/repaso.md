# Azure · Azure SQL Database · Repaso

## Preguntas de repaso
1. ¿Qué es Azure SQL Database en una frase?
   - *SQL Server como servicio: tablas, T-SQL y transacciones ACID, con parches, copias y alta disponibilidad a cargo de Azure.*
2. ¿Qué es el servidor lógico?
   - *Un punto de administración con DNS (`<nombre>.database.windows.net`), firewall y Entra; no es una máquina.*
3. ¿Qué diferencia hay entre Database, Managed Instance y SQL Server en VM?
   - *PaaS por base; instancia casi completa en tu red; control total del SO.*
4. ¿Qué es serverless y cuál es su pega?
   - *Escala entre mín. y máx. de vCores y se pausa; la primera conexión tras la pausa tarda.*
5. ¿Qué es un elastic pool?
   - *Capacidad compartida entre muchas bases con picos en momentos distintos.*
6. ¿Qué niveles de servicio hay?
   - *General Purpose, Business Critical, Hyperscale.*
7. ¿Cómo autentico una aplicación sin contraseña?
   - *Identidad administrada + `CREATE USER ... FROM EXTERNAL PROVIDER` + `authentication=ActiveDirectoryManagedIdentity`.*
8. ¿Qué es PITR y qué es LTR?
   - *Restaurar a un instante dentro de 1–35 días; conservar copias hasta 10 años.*
9. ¿Cómo se restaura una base?
   - *Se crea otra base; luego decides cuál usar.*
10. ¿Qué es un failover group?
    - *Dos servidores en regiones distintas con DNS estable que sigue a la primaria.*
11. ¿Qué errores son transitorios y qué haces?
    - *40613, 40501, 40197, 49918, 10928/10929, 1205: reintento con retroceso (solo operaciones idempotentes).*
12. ¿Por qué un pool grande puede perjudicar?
    - *`pods × pool` satura workers/sesiones de la base: más conexiones = más cola.*
13. ¿Qué es Query Store y para qué sirve?
    - *Historial de consultas y planes; permite detectar y forzar el plan bueno.*
14. ¿Qué hace `@Version`?
    - *Concurrencia optimista: el `UPDATE` falla si alguien cambió la fila; se responde 409.*
15. ¿Por qué usar Outbox?
    - *No hay transacción base-bus; la tabla `outbox` asegura que dato y evento se guarden juntos.*
16. ¿Qué es RLS y cuándo lo usas?
    - *Filtro automático de filas por inquilino con `SESSION_CONTEXT`; aislamiento multi-cliente.*
17. ¿El rol Contributor da acceso a los datos?
    - *No: los permisos de datos se otorgan dentro de la base.*

## Entrevista
- Diseña la base de pedidos para 3 regiones con RPO ≤ 5 min y RTO ≤ 30 min. ¿Nivel, redundancia, failover group, pruebas?
- Una consulta pasó de 40 ms a 6 s sin cambios de código. ¿Qué investigas y cómo lo arreglas?
- ¿Cómo evitas que un error de aplicación filtre datos de otro cliente?
- ¿Cómo despliegas una columna obligatoria sin caída?
- ¿Cómo dimensionas el pool de conexiones de 30 pods?

## Ejercicio práctico
1. Despliega el [Terraform](ejemplos/terraform/main.tf) en `dev`.
2. Ejecuta [01-usuarios-y-roles.sql](ejemplos/sql/01-usuarios-y-roles.sql) y [04-esquema-pedidos.sql](ejemplos/sql/04-esquema-pedidos.sql).
3. Conecta una aplicación Spring Boot con identidad (o `ActiveDirectoryDefault` desde tu máquina).
4. Provoca un conflicto de `@Version` y un deadlock; observa los reintentos.
5. Implementa el Outbox y publica a [Service Bus](../../07-mensajeria/service-bus/README.md).
6. Borra filas "por error" y restaura con PITR.
7. Activa RLS y prueba con dos inquilinos.
8. Revisa Query Store con [03-diagnostico.sql](ejemplos/sql/03-diagnostico.sql).
