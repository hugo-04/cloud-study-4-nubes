# AWS · Lambda · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. El mensaje malo que repetía todo el lote
**Qué pasó:** un pedido con formato inválido hacía fallar el lote de 10; los 9 buenos se reprocesaban y se enviaban correos duplicados. **Solución:** `ReportBatchItemFailures` y procesamiento idempotente por `pedidoId`. **Lección:** un mensaje malo no debe castigar a los buenos.

## 2. La cola que reaparecía cada 30 segundos
**Qué pasó:** la función tardaba 60 s y la cola tenía visibilidad de 30 s: los mensajes volvían mientras se procesaban. **Solución:** visibilidad ≥ 6 × timeout de la función. **Lección:** timeouts coordinados entre cola y función.

## 3. Cold start de 8 segundos
**Qué pasó:** una función Spring completa tardaba 8 s en frío y el primer cliente de la mañana esperaba. **Solución:** SnapStart + reducir dependencias + más memoria; el p99 bajó a ~1 s. **Lección:** en Java se mide el Init y se ataca con SnapStart y menos clases.

## 4. La cuenta sin concurrencia
**Qué pasó:** una avalancha de mensajes consumió la concurrencia de la cuenta y otras funciones críticas empezaron a limitarse (`Throttles`). **Solución:** `maximum_concurrency` en el origen y concurrencia reservada para lo crítico. **Lección:** la concurrencia es un recurso compartido.

## 5. Sin salida a Internet dentro de la VPC
**Qué pasó:** al meter la función en la VPC para llegar a la base de datos, dejó de llamar a un servicio externo. **Solución:** NAT para el externo y endpoints para AWS. **Lección:** en VPC no hay salida por defecto.

## 6. Función que olvidó cerrar el estado
**Qué pasó:** una variable estática acumulaba datos entre invocaciones y mezcló pedidos de clientes distintos. **Solución:** estado por invocación en variables locales; solo clientes y configuración inmutable son estáticos. **Lección:** el entorno se reutiliza.

| Problema | Solución |
|---|---|
| Lote repetido | Fallos parciales + idempotencia |
| Mensajes que reaparecen | Visibilidad ≥ 6×timeout |
| Arranque lento | SnapStart + menos clases |
| Concurrencia agotada | Máximo en origen + reservada |
| Sin salida en VPC | NAT / endpoints |
| Estado compartido | Estado local, no estático |
