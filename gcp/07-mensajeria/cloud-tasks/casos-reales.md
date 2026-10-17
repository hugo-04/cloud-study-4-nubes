# Google Cloud · Mensajería · Cloud Tasks · Casos reales

## 1. Tres recordatorios por carrito
**Qué pasó:** clientes de ModaLima recibían el recordatorio del carrito tres veces.
**Causa:** reintentos al crear la tarea sin nombre.
**Arreglo:** nombre `recordatorio-<idCarrito>-<fecha>`; el duplicado falla con `ALREADY_EXISTS` y se ignora.
**Lección:** el nombre es la clave de idempotencia.

## 2. La API del courier bloqueada
**Qué pasó:** el proveedor de envíos bloqueó a Café Andino por exceso de llamadas.
**Causa:** llamadas directas desde cada réplica sin control.
**Arreglo:** cola con 5 despachos por segundo hacia un servicio que llama al courier.
**Lección:** la cola es el regulador.

## 3. Tareas que nunca terminaban
**Qué pasó:** la cola de reportes acumulaba tareas reintentándose.
**Causa:** el destino respondía 500 ante datos inválidos.
**Arreglo:** responder 2xx con error registrado para fallas permanentes; reintentos con tope.
**Lección:** el código de respuesta controla los reintentos.

## 4. El destino público
**Qué pasó:** un endpoint de tareas internas podía llamarse desde Internet.
**Causa:** Cloud Run público «para que Cloud Tasks llegue».
**Arreglo:** OIDC con la SA de despacho y `run.invoker` solo para ella.
**Lección:** Cloud Tasks sabe autenticarse.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Duplicados | Sin nombre | Nombre determinista |
| 2 | Bloqueo externo | Sin tasa | Cola reguladora |
| 3 | Reintentos eternos | 500 en permanentes | 2xx + registro |
| 4 | Endpoint expuesto | Público | OIDC |
