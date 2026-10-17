# Oracle OCI · Mensajería · Queue · Casos reales

## 1. El correo de confirmación triplicado
**Qué pasó:** clientes de ModaLima recibían tres correos por compra en horas punta.
**Causa:** el envío tardaba más que la visibilidad (30 s) y el mensaje se reentregaba a otra réplica.
**Arreglo:** visibilidad de 120 s, extensión con `UpdateMessage` en trabajos largos y registro de idempotencia por id de pedido.
**Lección:** la visibilidad debe cubrir el peor caso razonable.

## 2. El mensaje venenoso
**Qué pasó:** un pedido con un carácter inválido bloqueaba a los consumidores reintentándose sin parar.
**Causa:** sin DLQ.
**Arreglo:** DLQ tras 5 entregas y alarma sobre su tamaño.
**Lección:** un mensaje que siempre falla debe salir del camino.

## 3. La factura de las consultas vacías
**Qué pasó:** Café Andino pagaba millones de solicitudes con la cola casi vacía.
**Causa:** consumidores sondeaban sin long polling.
**Arreglo:** `timeoutInSeconds = 20`.
**Lección:** espera en el servidor, no en un bucle.

## 4. Pedidos perdidos al reiniciar
**Qué pasó:** al desplegar, algunos pedidos no se facturaban.
**Causa:** el consumidor borraba el mensaje al recibirlo y luego moría el pod.
**Arreglo:** borrar solo tras confirmar el procesamiento.
**Lección:** el borrado es el «recibido conforme».

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Duplicados | Visibilidad corta | Visibilidad adecuada + idempotencia |
| 2 | Consumidores atascados | Sin DLQ | DLQ + alarma |
| 3 | Costo alto | Sin long polling | `timeoutInSeconds` |
| 4 | Mensajes perdidos | Borrado temprano | Borrar al final |
