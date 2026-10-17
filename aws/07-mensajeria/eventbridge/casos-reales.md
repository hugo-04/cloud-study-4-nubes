# AWS · EventBridge · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. La regla que nunca se activaba
**Qué pasó:** la regla de facturación no recibía nada. El productor enviaba `DetailType: "ordenCreada"` y el patrón decía `"OrdenCreada"`. **Solución:** los patrones distinguen mayúsculas; se agregó una prueba con `test-event-pattern` en el pipeline. **Lección:** prueba cada patrón con un evento real antes de desplegar.

## 2. El evento que se perdió en silencio
**Qué pasó:** la regla coincidía, pero la cola destino no tenía política para `events.amazonaws.com`; la métrica `FailedInvocations` subía y nadie la miraba. **Solución:** política de la cola con `aws:SourceArn` de la regla, DLQ en el destino y alarma. **Lección:** un destino sin permiso no avisa a nadie por sí solo.

## 3. HTTP 200 con tres eventos caídos
**Qué pasó:** en un lote de 10, `PutEvents` respondió 200 pero `FailedEntryCount` era 3 por limitación temporal. **Solución:** reintentar solo las entradas fallidas, con espera creciente, y separar errores definitivos. **Lección:** la respuesta es por entrada, no por llamada.

## 4. Reproducir el martes
**Qué pasó:** un error en logística dejó 4 000 órdenes sin procesar. **Solución:** corregir el código y **reproducir** desde el archivo el rango afectado hacia el bus; los consumidores eran idempotentes, así que no hubo duplicados. **Lección:** archivar da una segunda oportunidad, pero solo si procesar dos veces es seguro.

## 5. Reaccionar a lo que AWS ya sabe
**Qué pasó:** Café Andino sondeaba un bucket cada minuto para detectar cargas. **Solución:** el bucket envía sus eventos a EventBridge; una regla en el bus predeterminado manda «Object Created» de ese bucket a una cola. **Lección:** muchos servicios ya emiten eventos; no hagas *polling*. (Detalle: [eventos de S3](../../06-storage/eventos-s3/README.md)).

## 6. Un bus por dominio, y el cierre de caja a las 23:00 de Lima
**Qué pasó:** todos los equipos usaban el bus predeterminado y se pisaban las reglas; además, el cierre de caja corría a las 18:00 por estar en UTC. **Solución:** bus propio por dominio con política que solo permite `PutEvents` a cuentas conocidas, y un *schedule* con zona horaria `America/Lima`. **Lección:** separa por dominio y no hagas cron en UTC a mano.

## Resumen

| # | Problema | Pieza que lo resolvió |
|---|---|---|
| 1 | Patrón con otra mayúscula | `test-event-pattern` en CI |
| 2 | Destino sin permiso | Política de la cola + DLQ + alarma |
| 3 | Fallo parcial en `PutEvents` | Reintento por entrada |
| 4 | Error de código en un consumidor | Archivo + replay + idempotencia |
| 5 | Polling a S3 | Evento de servicio → regla |
| 6 | Bus único y cron en UTC | Bus por dominio + Scheduler |
