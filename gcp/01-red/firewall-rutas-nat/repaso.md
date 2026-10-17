# Google Cloud · Red · Firewall, rutas y Cloud NAT · Repaso

## Preguntas
1. ¿Qué tráfico permiten y deniegan las reglas implícitas?
2. ¿Qué número de prioridad gana?
3. ¿Por qué objetivos por cuenta de servicio?
4. ¿Qué se evalúa primero: políticas jerárquicas o reglas de VPC?
5. ¿Qué hace `goto_next`?
6. ¿Qué significa que el firewall es con estado?
7. ¿Para qué sirve Cloud Router con NAT?
8. ¿Qué pasa si se agotan los puertos de NAT?
9. ¿Cómo se hace SSH sin IP pública?
10. ¿Por qué reservar IPs de NAT?

## Respuestas
1. Entrada denegada, salida permitida.
2. El menor.
3. Porque una etiqueta la cambia quien edita la VM; la cuenta de servicio es identidad.
4. Las jerárquicas.
5. Delega la decisión al siguiente nivel.
6. Las respuestas de conexiones permitidas vuelven sin otra regla.
7. Es el plano de control de NAT (y BGP).
8. Las nuevas conexiones fallan.
9. Con IAP TCP forwarding.
10. Para que terceros puedan ponerlas en lista blanca.

## Ejercicios
1. Escribe la política jerárquica que deniega 22/3389 desde Internet.
2. Diseña las reglas entre balanceador, apps y base por cuenta de servicio.
3. Dimensiona puertos NAT para 40 VMs con 2.000 conexiones salientes cada una.
