# AWS · API Gateway · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. La API móvil que sobrepasó el presupuesto
**Qué pasó:** la app móvil de ModaLima usaba REST API con funciones que no necesitaba y el costo por petición era alto. **Solución:** migrar a HTTP API con autorizador JWT (misma funcionalidad útil, mucho más barata). **Lección:** elige el tipo por funciones necesarias, no por costumbre.

## 2. El 504 de los informes
**Qué pasó:** generar un informe tardaba 40 s y el cliente recibía 504 a los 30 s. **Solución:** la API responde `202 Accepted` con un `idTrabajo`, el trabajo se encola y el cliente consulta el estado. **Lección:** API Gateway no es para esperas largas.

## 3. El autorizador que se llamaba mil veces por segundo
**Qué pasó:** un autorizador Lambda consultaba la base en cada petición y la saturó. **Solución:** habilitar caché del resultado (TTL de 5 min) por token. **Lección:** cachea las decisiones de autorización.

## 4. Servicios privados sin abrir la red
**Qué pasó:** se quería exponer el servicio de Pedidos (en subredes privadas) sin balanceador público. **Solución:** HTTP API + VPC Link hacia un ALB interno. **Lección:** la API pública no exige servicios públicos.

## 5. Cliente que saturaba un endpoint caro
**Qué pasó:** un integrador llamaba a `/busqueda` miles de veces por minuto. **Solución:** throttling por ruta y, para integradores, REST API con plan de uso y clave. **Lección:** limita por ruta y por cliente.

## 6. Confiar en el gateway y nada más
**Qué pasó:** un servicio interno aceptaba cualquier petición «porque ya pasó por API Gateway»; un equipo lo expuso por error con otro balanceador. **Solución:** el servicio valida el JWT y el SG solo admite el VPC Link. **Lección:** defensa en profundidad.

| Problema | Solución |
|---|---|
| Costo alto en REST | HTTP API |
| 504 por tareas largas | 202 + asíncrono |
| Autorizador saturado | Caché del autorizador |
| Servicios privados | VPC Link + ALB interno |
| Abuso de un endpoint | Throttling / plan de uso |
| Confianza ciega | Validación en el backend |
