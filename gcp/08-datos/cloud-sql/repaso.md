# Google Cloud · Datos · Cloud SQL · Repaso

## Preguntas
1. ¿Qué motores ofrece?
2. ¿Qué aporta HA regional?
3. ¿Para qué sirven las réplicas de lectura?
4. ¿Qué es el connection name?
5. ¿Qué hace el conector Java?
6. ¿Cómo se entra sin contraseña?
7. ¿Qué roles necesita la app?
8. ¿Cómo calculas el pool?
9. ¿Qué es PITR?
10. ¿Qué política evita IP pública?

## Respuestas
1. PostgreSQL, MySQL y SQL Server.
2. Standby en otra zona con conmutación automática.
3. Lecturas escaladas y DR entre regiones.
4. `proyecto:región:instancia`.
5. Abre un túnel TLS autorizado por IAM sin listas de IP.
6. Autenticación IAM: el token de la SA es la credencial.
7. `cloudsql.client` y `cloudsql.instanceUser`.
8. Pool × instancias máximas ≤ `max_connections` menos reserva.
9. Recuperación a un instante dentro de la retención de registros.
10. `sql.restrictPublicIp`.

## Ejercicios
1. Calcula el pool para 30 instancias y 500 conexiones.
2. Escribe la URL JDBC con IAM auth.
3. Planea un simulacro de PITR.
