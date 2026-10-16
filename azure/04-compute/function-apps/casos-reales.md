# Azure · Function Apps · Casos reales

(ModaLima y Café Andino son empresas inventadas para estudiar.)

## Caso 1 · Miniaturas automáticas
- **Problema:** las fotos de producto se subían con 8 MB y la tienda era lenta.
- **Solución:** una función con `@BlobTrigger(source = "EventGrid")` genera tres tamaños y los guarda en otro contenedor.
- **Resultado:** páginas más rápidas y costo casi nulo.
- **Lección:** tareas por evento = serverless. Y usa Event Grid como origen: el sondeo de blobs puede tardar minutos.

## Caso 2 · El correo que se envió dos veces
- **Problema:** clientes recibían dos confirmaciones de pedido.
- **Causa:** el host reintentó la invocación tras un timeout de red; la función enviaba el correo **antes** de registrar que había procesado el mensaje.
- **Solución:** clave de idempotencia (`messageId`) en una tabla; si ya existe, se omite el envío.
- **Lección:** *al menos una vez* implica duplicados. Diseña para ellos.

## Caso 3 · El mensaje envenenado
- **Problema:** un pedido con un campo inválido fallaba siempre y bloqueaba la métrica de "cola vacía" durante horas.
- **Solución:** `maxDeliveryCount = 5`, la DLQ con alerta, y una función que deja pasar los inválidos a una cola de revisión manual.
- **Lección:** todo flujo necesita una salida para lo que no se puede procesar.

## Caso 4 · Arranque en frío en el checkout
- **Problema:** el primer cliente de la mañana esperaba 6 segundos.
- **Causa:** plan de consumo sin instancias activas y JVM arrancando.
- **Solución:** Flex Consumption con **2 instancias always-ready** para el grupo HTTP y memoria de 2 GB.
- **Lección:** mide el p95 de la primera petición; la latencia es parte del requisito.

## Caso 5 · La clave de función en el JavaScript del sitio
- **Problema:** un front-end llamaba a una función con `?code=<clave>` incluida en el código público.
- **Solución:** función `ANONYMOUS` + autenticación Entra ID (Easy Auth); la clave rotada; el front obtiene un token.
- **Lección:** una clave de función es un secreto, no una identidad de usuario.

## Caso 6 · El bucle que costó dinero
- **Problema:** la factura se disparó el fin de semana.
- **Causa:** la función de miniaturas escribía el resultado en el **mismo contenedor** que la disparaba; cada miniatura generaba otro evento.
- **Solución:** contenedores separados (`originales` / `miniaturas`) y un filtro por prefijo en la suscripción.
- **Lección:** salida y entrada nunca deben apuntar a la misma fuente de eventos.

## Caso 7 · La aprobación que espera tres días
- **Problema:** los pedidos grandes requerían aprobación manual; se "dormía" un hilo o se guardaba el estado a mano.
- **Solución:** orquestación Durable: reserva stock → espera evento externo de aprobación con *timeout* de 72 h → confirma o libera.
- **Lección:** esperar días no cuesta cómputo con Durable; el estado vive en el historial.

## Caso 8 · Dejar de usar claves de Storage
- **Problema:** `AzureWebJobsStorage` guardaba una cadena con la clave de la cuenta en los settings.
- **Solución:** `AzureWebJobsStorage__accountName` + roles de datos a la identidad y `allowSharedKeyAccess=false`.
- **Lección:** el host también puede ir sin secretos.

## Caso 9 · Del `@Scheduled` al timer
- **Problema:** el resumen diario se ejecutaba tres veces en App Service (tres instancias).
- **Solución:** moverlo a un **timer trigger**, que usa un *lease* para ejecutarse una sola vez.
- **Lección:** las tareas programadas en una plataforma con N instancias necesitan un coordinador; el timer ya lo trae.
