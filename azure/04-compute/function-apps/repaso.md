# Azure · Function Apps · Repaso

## Preguntas de repaso
1. ¿Qué es un trigger y cuántos puede tener una función?
   - *El evento que la dispara; exactamente uno. Los bindings (entradas/salidas) pueden ser varios.*
2. ¿Qué garantiza la plataforma: *at-most-once*, *at-least-once* o *exactly-once*?
   - *At-least-once: por eso hay que ser idempotente.*
3. ¿Para qué sirve la cuenta de Storage del host?
   - *Claves, leases, checkpoints y estado de Durable. Sin acceso, el host no arranca.*
4. ¿Cómo se conecta un trigger a Service Bus sin cadena de conexión?
   - *Setting `CONEXION__fullyQualifiedNamespace` + identidad con *Data Receiver/Sender*.*
5. ¿Por qué el timer no se ejecuta en todas las instancias?
   - *Usa un lease en Storage: una sola ejecución a la vez.*
6. ¿Qué es un mensaje envenenado y qué haces con él?
   - *El que siempre falla; debe acabar en DLQ con alerta, no en un bucle.*
7. ¿Cuándo usar Durable Functions?
   - *Flujos largos, con esperas, aprobaciones, fan-out/fan-in o sagas.*
8. ¿Qué no puedes hacer en un orquestador Durable?
   - *Cosas no deterministas: hora actual, aleatorios, I/O.*
9. ¿Qué plan elegirías para baja latencia constante y por qué?
   - *Premium (instancias pre-calentadas) o Flex con *always-ready*.*
10. ¿Por qué `ANONYMOUS` no significa "sin seguridad"?
    - *Delegas la autenticación a la plataforma (Entra ID) o a tu código; las claves no identifican usuarios.*
11. ¿Por qué usar Event Grid como origen del blob trigger?
    - *Es rápido y fiable; el sondeo puede tardar y no se recomienda para flujos críticos.*
12. ¿Cómo evitas aplastar a la base de datos al escalar?
    - *`maxConcurrentCalls` bajo y `maximum-instance-count` limitado.*

## Entrevista
- Una función de pedidos envía correos duplicados: ¿cómo lo investigas y lo corriges?
- Diseña el flujo de un pedido grande que necesita aprobación manual hasta 72 horas.
- ¿Cuándo no usarías Functions para una API REST en Java?
- ¿Cómo reduces el arranque en frío de una función Java?
- ¿Qué implica `AzureWebJobsStorage__accountName` y qué roles necesita?

## Ejercicio práctico
1. Crea una Function App Flex con `ejemplos/cli/function-apps.sh` (secciones 1–5).
2. Despliega una función Service Bus con idempotencia y envía 10 mensajes, uno inválido.
3. Verifica que el inválido acaba en la DLQ.
4. Añade un timer y confirma en los logs que corre una sola vez con 2+ instancias.
