# Oracle OCI · Compute · Functions · Casos reales

## 1. La miniatura duplicada
**Qué pasó:** cada foto subida generaba dos miniaturas.
**Causa:** el evento se entregó dos veces y la función no era idempotente.
**Arreglo:** nombre determinista del resultado y comprobación previa.
**Lección:** diseña para «al menos una vez».

## 2. El arranque en frío del checkout
**Qué pasó:** la primera compra de la mañana tardaba 6 segundos.
**Causa:** función Java sin instancias calientes.
**Arreglo:** concurrencia aprovisionada y arranque más ligero.
**Lección:** mide la latencia del primer uso.

## 3. Tiempo máximo agotado
**Qué pasó:** procesos largos terminaban a medias.
**Causa:** trabajo de 10 minutos en una función de 5.
**Arreglo:** pasarlo a Container Instances.
**Lección:** las funciones son para trabajo corto.

## 4. Invocaciones en bucle
**Qué pasó:** una función se llamaba a sí misma indirectamente y consumió la cuota.
**Causa:** su resultado disparaba el mismo evento.
**Arreglo:** prefijos distintos para entrada y salida.
**Lección:** cuidado con los ciclos de eventos.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Duplicados | No idempotente | Resultado determinista |
| 2 | Latencia inicial | Arranque en frío | Concurrencia aprovisionada |
| 3 | Trabajo incompleto | Tiempo máximo | Otro servicio |
| 4 | Cuota agotada | Ciclo de eventos | Separar prefijos |
