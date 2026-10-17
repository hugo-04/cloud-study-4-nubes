# Google Cloud · Ingress y API · Entrada a GKE · Repaso

## Preguntas
1. ¿Qué crea GKE para un Gateway?
2. ¿Qué es una GatewayClass?
3. ¿Quién crea Gateway y quién HTTPRoute?
4. ¿Qué es container-native load balancing?
5. ¿Cómo haces un canario?
6. ¿Para qué HealthCheckPolicy?
7. ¿Cómo adjuntas Cloud Armor?
8. ¿Qué valor de XFF es el cliente real?
9. ¿Cuándo usar Service LoadBalancer?
10. ¿Por qué reservar la IP?

## Respuestas
1. Un balanceador de aplicación de Google con NEG hacia los pods.
2. El tipo de balanceador a crear.
3. Plataforma el Gateway; cada equipo su HTTPRoute.
4. El balanceador apunta a IPs de pods.
5. Con backendRefs ponderados.
6. Definir el chequeo de salud por servicio.
7. Con GCPBackendPolicy.
8. El penúltimo (el último es el balanceador).
9. Para TCP/UDP de capa 4.
10. Para que no cambie al recrear el Gateway.

## Ejercicios
1. Escribe el Gateway de plataforma y las rutas de dos equipos.
2. Diseña un canario 90/10 del servicio de pedidos.
3. Escribe la NetworkPolicy que acepta solo desde el balanceador.
