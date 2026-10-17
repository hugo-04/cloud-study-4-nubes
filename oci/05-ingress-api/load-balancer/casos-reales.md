# Oracle OCI · Ingress y API · Load Balancer · Casos reales

## 1. El chequeo que tumbó la base
**Qué pasó:** en el Cyber de ModaLima el catálogo se cayó entero, aunque las réplicas estaban vivas.
**Causa:** el chequeo de salud apuntaba a `/`, que consultaba la base; con la base lenta, todos los backends quedaron *critical* a la vez.
**Arreglo:** chequeo a un endpoint de *readiness* liviano y separado de la dependencia lenta.
**Lección:** el chequeo mide si la réplica puede atender, no si todo el sistema está perfecto.

## 2. Los 502 de cada despliegue
**Qué pasó:** cada despliegue producía un minuto de errores 502.
**Causa:** las réplicas se detenían sin drenar; el LB seguía enviando a conexiones cerradas.
**Arreglo:** drenar el backend, esperar a que se vacíe y recién entonces detenerlo.
**Lección:** quitar una réplica tiene tres pasos: drenar, esperar, detener.

## 3. El WebSocket que se cortaba
**Qué pasó:** el seguimiento en vivo de pedidos de Café Andino se desconectaba cada minuto.
**Causa:** `idle timeout` por defecto menor que el intervalo de mensajes.
**Arreglo:** subir el *timeout* del listener y enviar *pings* periódicos.
**Lección:** conexiones largas necesitan configuración explícita.

## 4. La IP que mentía
**Qué pasó:** el límite de intentos de inicio de sesión bloqueaba a todos los usuarios a la vez.
**Causa:** la app usaba la IP de la conexión, que siempre era la del LB.
**Arreglo:** leer `X-Forwarded-For` solo si viene del rango del LB.
**Lección:** detrás de un proxy, la IP del cliente viaja en una cabecera.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Caída total | Chequeo pesado | *Readiness* liviano |
| 2 | 502 al desplegar | Sin drenado | Drenar, esperar, detener |
| 3 | Cortes de WebSocket | `idle timeout` | Ajustar y *ping* |
| 4 | Bloqueo masivo | IP del LB | `X-Forwarded-For` confiable |
