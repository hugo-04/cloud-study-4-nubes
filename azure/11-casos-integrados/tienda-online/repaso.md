# Azure · Caso integrado · Tienda online · Repaso

## Preguntas
1. ¿Por qué no basta con «guardar y luego publicar»?
   - *Un corte entre ambos pasos pierde el evento; son dos sistemas sin transacción común.*
2. ¿Qué es la bandeja de salida y qué garantiza?
   - *Una tabla donde el evento se guarda con el pedido en una transacción; garantiza que no se pierde, no que se publica una sola vez.*
3. ¿Por qué el publicador puede publicar dos veces?
   - *Si muere después de enviar y antes de marcar la fila, al reiniciar vuelve a enviarla.*
4. ¿Cómo se evita el efecto de duplicados?
   - *`MessageId` determinista con detección de duplicados del bus y bandeja de entrada idempotente en el consumidor.*
5. ¿Para qué sirve `FOR UPDATE SKIP LOCKED`?
   - *Que varias réplicas tomen lotes distintos sin bloquearse ni repetirse.*
6. ¿Por qué el registro del `MessageId` y la lógica van en la misma transacción?
   - *Si la lógica falla, el registro se deshace y el reintento puede procesar de nuevo.*
7. ¿Qué viaja por el bus y qué por Blob?
   - *El evento pequeño con la referencia viaja por el bus; el archivo grande queda en Blob (Claim Check).*
8. ¿Por qué se responde `201` antes de facturar?
   - *La facturación es asíncrona; no debe bloquear ni romper la compra.*
9. ¿Qué requisito tiene Service Bus para usar Private Endpoint?
   - *El nivel Premium.*
10. ¿Qué rol necesita el pod que publica y cuál el que consume?
    - *Azure Service Bus Data Sender y Azure Service Bus Data Receiver, en el alcance mínimo.*
11. ¿Cómo se comprueba que la red privada funciona?
    - *Resolviendo el nombre y abriendo la conexión desde un pod: debe dar una IP privada.*
12. ¿Qué alertas son imprescindibles?
    - *Tamaño de la bandeja de salida, mensajes en la DLQ, errores 5xx y latencia por dependencia.*
13. ¿Por qué usar SAS de delegación de usuario con vencimiento corto?
    - *Se firma con una identidad de Entra ID (no con la clave de la cuenta) y limita el daño si el enlace se filtra.*
14. ¿Qué papel juegan Policy, bloqueos y presupuestos aquí?
    - *Exigir lo privado y las etiquetas, evitar borrados de producción y avisar del gasto.*

## Mini-ejercicios
1. Dibuja desde memoria los diez pasos de la compra y marca cuáles son síncronos.
2. Escribe la consulta que lista pedidos sin evento publicado en más de 5 minutos.
3. Añade una suscripción `analitica` al tópico: ¿qué cambia en `pedidos`? (Nada.)
4. Simula el corte entre «publicar» y «marcar» y demuestra que facturación procesa una sola vez.
5. Diseña la política que niega crear SQL con acceso público.

## Autoevaluación
- [ ] Explico la bandeja de salida sin mirar.
- [ ] Sé qué rol necesita cada servicio y a qué alcance.
- [ ] Sé comprobar la red privada desde un pod.
- [ ] Distingo qué va por evento y qué por llamada directa.
