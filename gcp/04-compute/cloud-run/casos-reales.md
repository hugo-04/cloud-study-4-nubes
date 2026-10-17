# Google Cloud · Compute · Cloud Run · Casos reales

## 1. La base sin conexiones
**Qué pasó:** en una campaña, Cloud Run escaló a 300 instancias y Cloud SQL rechazó conexiones.
**Causa:** sin máximo de instancias y pool de 10 por instancia.
**Arreglo:** máximo de 40 instancias, pool de 5 y concurrencia ajustada.
**Lección:** escalar sin límite traslada el problema a la base.

## 2. El primer clic lento
**Qué pasó:** la primera compra de la mañana tardaba 8 segundos.
**Causa:** arranque en frío de Spring Boot con escala a cero.
**Arreglo:** mínimo de 2 instancias, CPU boost al arrancar y arranque más liviano.
**Lección:** mide el arranque en frío de la JVM.

## 3. El servicio interno público
**Qué pasó:** el servicio de precios de ModaLima respondía a cualquiera en Internet.
**Causa:** `allUsers` como invoker «para probar».
**Arreglo:** invoker solo para la SA del llamador e ingress interno.
**Lección:** privado por defecto.

## 4. Los correos que nunca salieron
**Qué pasó:** Café Andino enviaba correos en un hilo de fondo después de responder; muchos no salían.
**Causa:** CPU asignada solo durante peticiones.
**Arreglo:** publicar en Pub/Sub y procesar en otro servicio (o CPU siempre asignada).
**Lección:** en Cloud Run, el trabajo ocurre dentro de la petición.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Conexiones rechazadas | Sin máximo | Máximo + pool chico |
| 2 | Latencia inicial | Escala a cero | Mínimo + CPU boost |
| 3 | API expuesta | `allUsers` | Invoker por SA |
| 4 | Trabajo perdido | Hilo de fondo | Pub/Sub o CPU siempre |
