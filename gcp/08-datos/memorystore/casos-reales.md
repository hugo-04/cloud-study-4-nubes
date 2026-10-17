# Google Cloud · Datos · Memorystore · Casos reales

## 1. La estampida de las 00:00
**Qué pasó:** a medianoche Cloud SQL de ModaLima se saturó.
**Causa:** todo el catálogo se cacheaba con TTL de 24 h desde la carga nocturna: vencía a la vez.
**Arreglo:** TTL con *jitter* de ±10 %.
**Lección:** desincroniza las caducidades.

## 2. La caché que tumbó la tienda
**Qué pasó:** en el mantenimiento de la caché, la app daba 500.
**Causa:** sin manejo de errores de Redis.
**Arreglo:** timeouts cortos y fallback a la base.
**Lección:** la caché es opcional para la correctitud.

## 3. `KEYS *` en producción
**Qué pasó:** un script de soporte de Café Andino congeló la caché.
**Causa:** comando O(n) bloqueante.
**Arreglo:** `SCAN` y permisos de solo lectura para soporte.
**Lección:** cuidado con los comandos pesados.

## 4. Memoria llena
**Qué pasó:** escrituras rechazadas con OOM.
**Causa:** claves sin TTL y política `noeviction`.
**Arreglo:** TTL siempre y `allkeys-lru`.
**Lección:** define qué pasa al llenarse.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Base saturada | TTL sincronizado | Jitter |
| 2 | 500 en mantenimiento | Sin fallback | Degradar |
| 3 | Bloqueo | `KEYS *` | `SCAN` |
| 4 | OOM | Sin TTL | TTL + LRU |
