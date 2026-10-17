# AWS · ALB y NLB · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. Los 502 cada madrugada
**Qué pasó:** clientes recibían 502 esporádicos. La aplicación cerraba conexiones inactivas a los 30 s y el ALB a los 60 s: reusaba una conexión ya cerrada. **Solución:** keep-alive de la aplicación a 75 s (mayor que el del ALB). **Lección:** el que cierra primero debe ser el balanceador.

## 2. Despliegues que tardaban cinco minutos
**Qué pasó:** `deregistration_delay` por defecto de 300 s: cada tarea retirada esperaba cinco minutos. **Solución:** 30 s alineado con el `stopTimeout` y el apagado ordenado. **Lección:** el valor por defecto no es el correcto para APIs rápidas.

## 3. El health check que mentía
**Qué pasó:** el health check apuntaba a `/` (siempre 200) mientras la base estaba caída; el ALB seguía enviando tráfico a tareas rotas. **Solución:** `/actuator/health/readiness` con la base como indicador de readiness. **Lección:** el health check debe reflejar si la instancia *puede servir*.

## 4. La IP de todos los clientes era la del ALB
**Qué pasó:** el límite de peticiones por IP bloqueaba a todos porque la aplicación veía la IP del balanceador. **Solución:** `forward-headers-strategy` y confiar en `X-Forwarded-For` solo desde el ALB. **Lección:** detrás de un balanceador, la IP real viene en una cabecera.

## 5. Lista blanca con IP fija
**Qué pasó:** un banco exigía una IP fija de origen y de destino. **Solución:** NLB con IP elástica para la entrada y NAT con IP elástica para la salida. **Lección:** cuando la IP importa, NLB.

## 6. Un ALB por microservicio
**Qué pasó:** 20 ALB con poco tráfico: costo fijo alto. **Solución:** un ALB compartido con reglas por host y ruta (y pesos para *canary*). **Lección:** el balanceador es compartible.

| Problema | Solución |
|---|---|
| 502 esporádicos | Keep-alive de la app > idle timeout |
| Despliegues lentos | Ajustar deregistration delay |
| Tráfico a tareas rotas | Health check de readiness |
| IP del cliente equivocada | Cabeceras de reenvío confiables |
| IP fija | NLB + EIP |
| Costo de muchos ALB | ALB compartido con reglas |
