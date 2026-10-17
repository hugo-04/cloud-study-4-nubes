# Google Cloud · Ingress y API · API Gateway · Casos reales

## 1. El backend que todos podían llamar
**Qué pasó:** alguien llamaba directo a la URL de Cloud Run de pedidos saltándose el gateway.
**Causa:** Cloud Run público.
**Arreglo:** servicio privado; solo la cuenta del gateway tiene `run.invoker`.
**Lección:** el gateway protege solo si es la única puerta.

## 2. La llave de API como identidad
**Qué pasó:** una llave de socio de Café Andino filtrada permitió crear pedidos a su nombre.
**Causa:** la escritura solo pedía llave de API.
**Arreglo:** JWT para operaciones de escritura; llave solo para cuotas y lectura.
**Lección:** una llave identifica, no autentica.

## 3. La configuración editada en caliente
**Qué pasó:** un cambio urgente en la consola rompió rutas y no se sabía qué cambió.
**Causa:** sin versionado.
**Arreglo:** especificación en Git, configuraciones nuevas por pipeline.
**Lección:** las configuraciones son inmutables por algo.

## 4. La ruta duplicada
**Qué pasó:** `/v1/pedidos/123` llegaba al backend como `/v1/pedidos/v1/pedidos/123`.
**Causa:** `path_translation` por defecto con una dirección que ya tenía ruta.
**Arreglo:** `APPEND_PATH_TO_ADDRESS` con dirección base sin ruta.
**Lección:** entiende cómo se traduce la ruta.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Bypass | Backend público | Privado + invoker |
| 2 | Suplantación | Llave como identidad | JWT |
| 3 | Rotura | Edición manual | Git + pipeline |
| 4 | Rutas raras | Traducción | `path_translation` |
