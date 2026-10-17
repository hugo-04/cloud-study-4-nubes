# Oracle OCI · Datos · OCI Cache · Casos reales

## 1. La estampida de medianoche
**Qué pasó:** a las 00:00 la base de ModaLima se saturó cada día.
**Causa:** todas las fichas de producto se cargaron con el mismo TTL al reiniciar y expiraron juntas.
**Arreglo:** TTL con jitter (±20 %) y un solo regenerador por clave.
**Lección:** la expiración sincronizada es un ataque contra tu base.

## 2. El precio viejo
**Qué pasó:** tras cambiar precios, la tienda mostró los antiguos por una hora.
**Causa:** TTL largo y sin invalidación.
**Arreglo:** versión del catálogo en la clave; al publicar precios se sube de `v3` a `v4`.
**Lección:** invalida por versión, no borrando claves una por una.

## 3. La caída por la caché
**Qué pasó:** durante un mantenimiento de la caché, el checkout devolvía 500.
**Causa:** la app trataba un *timeout* de la caché como error fatal.
**Arreglo:** *timeout* corto y degradar a la base si la caché no responde.
**Lección:** la caché acelera; no debe ser un punto único de falla.

## 4. `KEYS *` en producción
**Qué pasó:** un script de soporte de Café Andino congeló la caché unos segundos.
**Causa:** `KEYS *` sobre millones de claves.
**Arreglo:** `SCAN` con cursor y usuarios ACL sin permiso a comandos peligrosos.
**Lección:** algunos comandos bloquean el servidor completo.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Base saturada a hora fija | TTL sincronizado | Jitter + un regenerador |
| 2 | Datos viejos | Sin invalidación | Versión en la clave |
| 3 | 500 en checkout | Caché como dependencia dura | Degradar a la base |
| 4 | Congelamiento | `KEYS *` | `SCAN` + ACL |
