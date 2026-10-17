# Oracle OCI · Ingress y API · Load Balancer · Repaso

## Preguntas
1. ¿Qué une un listener con los backends?
2. ¿Qué políticas de balanceo hay?
3. ¿A qué endpoint debe apuntar el chequeo de salud?
4. ¿Qué hace `drain` en un backend?
5. ¿Qué significa un `504`?
6. ¿Dónde van el LB y los backends en la red?
7. ¿Cómo obtiene la app la IP real del cliente?
8. ¿Qué define la forma flexible?
9. ¿Cuándo prefieres un Network Load Balancer?
10. ¿Qué recurso de Terraform redirige HTTP a HTTPS?

## Respuestas
1. El backend set por defecto del listener (o las reglas de enrutamiento).
2. `ROUND_ROBIN`, `LEAST_CONNECTIONS`, `IP_HASH`.
3. A uno de *readiness* liviano.
4. Deja de enviarle conexiones nuevas y deja terminar las actuales.
5. El backend no respondió a tiempo.
6. LB en subred pública (o privada si es interno); backends en subred privada.
7. Con `X-Forwarded-For`, confiando solo si viene del LB.
8. El ancho de banda mínimo y máximo en Mbps.
9. Con IP de origen intacta, UDP o latencia mínima.
10. `oci_load_balancer_rule_set` con una regla `REDIRECT`.

## Ejercicios
1. Diseña el chequeo de salud del servicio de pedidos de ModaLima (URL, intervalo, reintentos).
2. Escribe los pasos de un despliegue sin 502 con 3 réplicas.
3. Calcula el ancho de banda mínimo para 2.000 peticiones/s de 15 KB.
