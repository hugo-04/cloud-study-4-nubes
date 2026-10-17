# Oracle OCI · Ingress y API · Ingress en OKE · Repaso

## Preguntas
1. ¿Qué crea OKE para un `Service type: LoadBalancer`?
2. ¿Cómo pides un NLB en lugar de un LB?
3. ¿Qué ventaja tiene el Ingress frente a un LB por servicio?
4. ¿A qué apunta el LB del controlador nativo?
5. ¿Qué requisito de red tiene eso?
6. ¿Para qué una IP pública reservada?
7. ¿Qué hace `externalTrafficPolicy: Local`?
8. ¿Por qué `preStop`?
9. ¿Cómo limitas quién crea LB públicos?
10. ¿Dónde va un API Gateway en este diseño?

## Respuestas
1. Un Load Balancer de OCI configurado por anotaciones.
2. Con la anotación `oci.oraclecloud.com/load-balancer-type: "nlb"`.
3. Un solo LB y reglas por host/ruta para muchos servicios.
4. Directo a las IPs de los pods.
5. Pods con red VCN-native.
6. Para que el IP no cambie si se recrea el Service.
7. Preserva la IP del cliente y envía solo a nodos con pods locales.
8. Para dar tiempo a que el LB saque el pod antes de terminarlo.
9. Con RBAC y una política de admisión.
10. Delante, apuntando a un Ingress interno.

## Ejercicios
1. Escribe el Ingress de catálogo, pedidos y pagos de ModaLima con TLS.
2. Diseña el `preStop` y los tiempos de apagado de un pod Spring Boot.
3. Escribe la política de admisión que impide `LoadBalancer` públicos.
