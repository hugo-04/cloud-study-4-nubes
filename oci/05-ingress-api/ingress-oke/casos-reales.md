# Oracle OCI · Ingress y API · Ingress en OKE · Casos reales

## 1. Doce balanceadores para doce servicios
**Qué pasó:** la factura de red de ModaLima se triplicó en un mes.
**Causa:** cada equipo exponía su microservicio con `Service type: LoadBalancer`.
**Arreglo:** un Ingress nativo compartido con reglas por ruta y una política de admisión que bloquea `LoadBalancer` fuera del namespace de plataforma.
**Lección:** un LB por servicio es caro y difícil de gobernar.

## 2. El DNS que apuntaba a la nada
**Qué pasó:** tras recrear el Service, la tienda quedó fuera de línea hasta actualizar el DNS.
**Causa:** el IP público era efímero y cambió.
**Arreglo:** IP pública reservada referenciada en la anotación.
**Lección:** reserva el IP de todo lo que vive en un DNS.

## 3. Errores en cada despliegue
**Qué pasó:** cada *rolling update* producía 502 durante 20 segundos.
**Causa:** los pods se terminaban antes de que el LB los sacara de rotación.
**Arreglo:** `preStop` con espera, apagado ordenado de Spring/Quarkus y *readiness gates* del controlador nativo.
**Lección:** el LB tarda en enterarse; dale tiempo.

## 4. Todos los usuarios con la misma IP
**Qué pasó:** el antifraude de Café Andino veía todas las compras desde IPs de nodos.
**Causa:** `externalTrafficPolicy: Cluster` y la app leía la IP del socket.
**Arreglo:** `Local` en el NLB y lectura de `X-Forwarded-For` confiable en el Ingress HTTP.
**Lección:** cada salto puede ocultar al cliente.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Costo alto | LB por servicio | Ingress compartido |
| 2 | Caída tras recrear | IP efímero | IP reservado |
| 3 | 502 al desplegar | Sin `preStop` | Apagado ordenado |
| 4 | IP de nodos | Política de tráfico | `Local` + XFF confiable |
