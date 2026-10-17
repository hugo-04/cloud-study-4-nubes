# Oracle OCI · Mensajería · Notifications · Casos reales

## 1. La suscripción que nadie confirmó
**Qué pasó:** una caída de la base de ModaLima no avisó a nadie.
**Causa:** la suscripción de correo de guardia seguía `PENDING`; el correo de confirmación fue a spam.
**Arreglo:** revisar estado de suscripciones en el pipeline y prueba mensual de alertas.
**Lección:** una alerta no probada no existe.

## 2. La tormenta de correos
**Qué pasó:** operaciones recibió 800 correos idénticos en 10 minutos y se perdió el aviso importante.
**Causa:** la app publicaba un aviso por cada error.
**Arreglo:** agrupación por clave en ventanas de 5 minutos con conteo.
**Lección:** agrupa antes de publicar.

## 3. El webhook que procesó dos veces
**Qué pasó:** el sistema de despacho de Café Andino creó dos guías para el mismo pedido.
**Causa:** reintento de entrega tras un *timeout* del webhook.
**Arreglo:** responder rápido (202) y deduplicar por id de mensaje.
**Lección:** los webhooks también son «al menos una vez».

## 4. Datos personales en el chat
**Qué pasó:** las alertas incluían el correo y la dirección del cliente.
**Causa:** el cuerpo llevaba el pedido completo.
**Arreglo:** solo identificadores y un enlace al panel interno.
**Lección:** las alertas viajan a lugares menos protegidos.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Sin aviso | Suscripción pendiente | Verificar y probar |
| 2 | Avisos ignorados | Tormenta | Agrupar |
| 3 | Doble proceso | Reintento | Idempotencia |
| 4 | Fuga de datos | Cuerpo completo | Solo identificadores |
