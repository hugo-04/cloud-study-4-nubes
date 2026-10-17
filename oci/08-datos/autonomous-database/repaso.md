# Oracle OCI · Datos · Autonomous Database · Repaso

## Preguntas
1. ¿Qué tipos de carga ofrece Autonomous?
2. ¿Qué servicio de conexión usas para OLTP?
3. ¿Qué diferencia hay entre TLS mutuo y one-way?
4. ¿Para qué sirve el endpoint privado?
5. ¿Qué hace Autonomous Data Guard?
6. ¿Qué es el autoescalado y qué riesgo tiene?
7. ¿Qué usuario usa la app?
8. ¿Cómo haces pruebas con datos de producción?
9. ¿Qué permiso necesita la app para leer los perfiles de conexión?
10. ¿Cuándo eliges MySQL o PostgreSQL en su lugar?

## Respuestas
1. Transaccional, *data warehouse*, JSON y APEX.
2. `tp` (o `tpurgent` para lo crítico).
3. El mutuo exige wallet en el cliente; el one-way solo cifra y valida al servidor.
4. Para que la base solo sea accesible dentro de la VCN.
5. Mantiene un standby y permite *failover*.
6. Usa hasta 3× el cómputo base; puede disparar el costo.
7. Un usuario propio con privilegios mínimos.
8. Con clones enmascarados.
9. `read autonomous-databases`.
10. Cuando la aplicación está hecha para esos motores.

## Ejercicios
1. Dimensiona pools y servicio para 6 réplicas del servicio de pedidos.
2. Diseña el proceso de clon enmascarado semanal.
3. Escribe la URL JDBC con reintentos para el perfil `tp`.
