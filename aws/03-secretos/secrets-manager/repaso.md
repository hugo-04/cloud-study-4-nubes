# AWS · Secrets Manager · Repaso

## Preguntas
1. ¿Qué etiqueta marca la versión vigente?
   - *`AWSCURRENT`.*
2. ¿Qué hace la Lambda de rotación en sus cuatro pasos?
   - *Crea, aplica, prueba y finaliza la nueva credencial.*
3. ¿Qué ventaja tiene la rotación de usuarios alternos?
   - *Evita cortes durante el cambio.*
4. ¿Por qué cachear el secreto en la aplicación?
   - *Menos costo y latencia, evita el estrangulamiento.*
5. ¿Qué haces si falla la autenticación a la base después de rotar?
   - *Recargas el secreto y reintentas con la credencial nueva.*
6. ¿Cuándo necesitas una CMK en lugar de la clave gestionada?
   - *Para acceso entre cuentas.*
7. ¿Cuál es la ventana de recuperación al borrar?
   - *De 7 a 30 días.*
8. ¿Cuándo se inyecta un secreto en una tarea de ECS?
   - *Al arrancar la tarea; no se refresca solo.*
9. ¿Secrets Manager o Parameter Store para una bandera de configuración?
   - *Parameter Store.*
10. ¿Cómo se ve quién leyó un secreto?
    - *En CloudTrail.*

## Ejercicios
1. Diseña la convención de nombres para tres servicios y dos entornos.
2. Escribe la política IAM mínima para leer un secreto con CMK.
3. Calcula el costo mensual de 40 secretos y 5 millones de llamadas con y sin caché.
4. Define el procedimiento de rotación de la base de pedidos con usuarios alternos.

## Autoevaluación
- [ ] Sé explicar las versiones y etiquetas.
- [ ] Sé qué hace cada paso de la rotación.
- [ ] Sé reaccionar en la aplicación a una rotación.
- [ ] Sé cuándo usar Parameter Store en su lugar.
