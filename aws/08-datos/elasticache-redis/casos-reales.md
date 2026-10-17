# AWS · ElastiCache · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. El catálogo que tumbó la base en la campaña
**Qué pasó:** cada visita a la portada ejecutaba las mismas consultas pesadas; en la campaña, la base llegó al límite de CPU. **Solución:** *cache-aside* con TTL de 10 minutos ± 20 % y un TTL corto para «no existe». **Resultado:** el 95 % de las lecturas salió de la caché. **Lección:** cachea lo caro y repetido, no todo.

## 2. La estampida del lunes a las 9
**Qué pasó:** una clave muy popular venció; 800 peticiones simultáneas fallaron y todas fueron al origen a la vez. **Solución:** una sola petición recalcula (los demás esperan su resultado) y TTL con azar para que las claves no venzan juntas. **Lección:** el vencimiento es un evento; hay que diseñarlo.

## 3. La API de socios que se quedó sin cuota
**Qué pasó:** un socio disparó miles de llamadas por minuto y degradó a los demás. **Solución:** límite por clave de API con un contador por ventana (`INCR` + `EXPIRE` en un script) y respuesta `429` con `Retry-After`. **Lección:** el contador y su vencimiento deben ser atómicos (un script, no dos comandos).

## 4. El informe generado dos veces
**Qué pasó:** dos instancias lanzaron el mismo informe nocturno a la vez. **Solución:** candado con `SET NX PX` y token propio, liberado solo si el token coincide (script). **Lección:** soltar un candado ajeno es peor que no tener candado; y si la tarea dura más que el vencimiento, hay dos dueños — la tarea debe ser idempotente.

## 5. `CROSSSLOT` el día que migraron a modo clúster
**Qué pasó:** al pasar a modo clúster, una operación que leía el carrito y su descuento falló con `CROSSSLOT`. **Solución:** etiquetas de hash (`carrito:{cliente-42}:items` y `carrito:{cliente-42}:descuento`) para que compartan slot. **Lección:** en modo clúster, diseña las claves relacionadas juntas.

## 6. El failover que tardó «eternamente»
**Qué pasó:** tras una caída del primario, la aplicación siguió escribiendo en el nodo viejo y recibió errores `READONLY` durante minutos. **Solución:** TTL de DNS corto en la JVM, reconexión que no almacene comandos, y reintento con espera. **Lección:** el failover cambia el DNS; la aplicación debe poder seguirlo.

## Resumen

| # | Problema | Pieza que lo resolvió |
|---|---|---|
| 1 | Base saturada | Cache-aside + TTL con azar + caché negativa |
| 2 | Estampida | Una sola recarga por clave |
| 3 | Cuota de socios | Contador por ventana atómico |
| 4 | Doble ejecución | Candado con token + liberación condicional |
| 5 | `CROSSSLOT` | Etiquetas de hash |
| 6 | Failover lento | DNS corto + fallo rápido + reintento |
