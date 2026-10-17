# Oracle OCI · Ingress y API · Network Load Balancer · Repaso

## Preguntas
1. ¿En qué capa trabaja el NLB?
2. ¿Qué protocolos acepta?
3. ¿Qué hace la preservación de origen?
4. ¿Qué regla de NSG cambia al preservar origen?
5. ¿Dónde se termina TLS con un NLB?
6. ¿Qué es el hash de 5-tupla?
7. ¿Cuándo usar hash simétrico?
8. ¿Por qué preferir chequeo HTTP?
9. ¿Se puede poner WAF delante del NLB?
10. ¿Tiene forma con ancho de banda?

## Respuestas
1. Capa 4.
2. TCP, UDP, ICMP (listener `ANY` para todos los puertos).
3. El backend ve la IP real del cliente.
4. El backend debe permitir las IPs de los clientes, no solo la subred del NLB.
5. En el backend.
6. Elegir backend según IP y puerto de origen y destino más protocolo.
7. Con *appliances* con estado como *firewalls*.
8. Porque comprueba que el servicio funciona, no solo que el puerto abre.
9. No; el WAF se adjunta al Load Balancer de capa 7.
10. No; escala solo.

## Ejercicios
1. Diseña el NLB privado del clúster Kafka de ModaLima (listeners, chequeo, NSG).
2. Escribe las reglas de NSG de un backend con preservación de origen.
3. Decide LB o NLB para: API REST pública, syslog UDP, PostgreSQL interno.
