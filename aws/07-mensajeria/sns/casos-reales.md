# AWS · SNS · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. Una orden, cuatro sistemas
**Qué pasó:** la API de órdenes llamaba por HTTP a facturación, logística, notificaciones y analítica; cuando uno se caía, la orden fallaba. **Solución:** la API publica en un tópico y cada sistema tiene su cola suscrita. **Lección:** quien publica no debe saber quién escucha.

## 2. El consumidor que ignoraba el 90 %
**Qué pasó:** logística recibía todos los eventos y descartaba lo que no era envío a domicilio. **Solución:** política de filtro `{"envio":["domicilio"]}` en su suscripción. **Lección:** filtra en el tópico, no en el consumidor.

## 3. El sobre inesperado
**Qué pasó:** un consumidor esperaba el JSON de la orden y recibía `{"Type":"Notification","Message":"{\"idOrden\":...}"}`. **Solución:** entrega cruda en las suscripciones propias; en las que no, desempaquetar el sobre. **Lección:** SNS agrega un sobre salvo que pidas entrega cruda.

## 4. El filtro que no filtraba
**Qué pasó:** el filtro `{"total":[{"numeric":[">",100]}]}` no entregaba nada: el publicador mandaba `total` como String. **Solución:** atributo con `DataType = Number`. **Lección:** el tipo del atributo importa.

## 5. Mensajes perdidos en silencio
**Qué pasó:** una Lambda suscrita fallaba y nadie lo notaba. **Solución:** SNS → SQS → Lambda con DLQ y alarma, en lugar de Lambda directa. **Lección:** una cola entre medias hace visibles los fallos.

## 6. Dos veces el mismo SMS
**Qué pasó:** SNS entregó dos veces (al menos una) y el cliente recibió dos avisos. **Solución:** idempotencia con `MessageId` y, para flujos con orden, tópico FIFO con deduplicación. **Lección:** diseña para duplicados.

| Problema | Solución |
|---|---|
| Acoplamiento punto a punto | Fan-out con SNS → SQS |
| Mensajes que sobran | Políticas de filtro |
| Sobre inesperado | Raw delivery o desempaquetar |
| Filtro numérico inútil | Atributo `Number` |
| Fallos silenciosos | Cola + DLQ + alarma |
| Duplicados | Idempotencia / FIFO |
