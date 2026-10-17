# Oracle OCI · Ingress y API · Network Load Balancer · Casos reales

## 1. El backend que no veía a nadie
**Qué pasó:** al activar la preservación de origen, el NLB dejó de entregar tráfico a la pasarela MQTT de Café Andino.
**Causa:** el NSG del backend solo permitía la subred del NLB; ahora los paquetes llegaban con la IP del cliente.
**Arreglo:** permitir los rangos de clientes en el puerto del servicio y la subred del NLB para el chequeo.
**Lección:** preservar el origen cambia quién debe estar en las reglas.

## 2. Puerto abierto, servicio muerto
**Qué pasó:** el clúster de búsqueda devolvía errores, pero el NLB lo marcaba sano.
**Causa:** chequeo TCP; el proceso aceptaba conexiones aunque estuviera atascado.
**Arreglo:** chequeo HTTP a un endpoint de salud real.
**Lección:** «el puerto abre» no es «el servicio funciona».

## 3. El firewall que perdía la mitad
**Qué pasó:** con dos *firewalls* virtuales detrás de un NLB, la mitad de las conexiones se colgaba.
**Causa:** ida por un *firewall* y vuelta por otro (hash asimétrico).
**Arreglo:** hash simétrico y preservar origen/destino.
**Lección:** los *appliances* con estado necesitan simetría.

## 4. TLS en el lugar equivocado
**Qué pasó:** un equipo intentó subir el certificado al NLB y no encontró dónde.
**Causa:** el NLB no termina TLS.
**Arreglo:** certificado en el backend (TLS de extremo a extremo) o cambiar a Load Balancer.
**Lección:** capa 4 no abre el paquete.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Sin tráfico tras preservar origen | NSG del backend | Permitir IPs de clientes |
| 2 | Sano pero falla | Chequeo TCP | Chequeo HTTP |
| 3 | Conexiones colgadas | Asimetría | Hash simétrico |
| 4 | ¿Dónde va el certificado? | NLB es capa 4 | Backend o LB de capa 7 |
