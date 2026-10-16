# Azure · Event Grid · Repaso

## Preguntas de repaso
1. ¿Qué es Event Grid en una frase?
   - *Un enrutador de eventos sin servidores: publicas "algo pasó" y se entrega, filtrado, a quien se suscribió.*
2. ¿Qué diferencia hay entre evento y mensaje?
   - *Evento: hecho ya ocurrido, avisa. Mensaje: contrato de trabajo por hacer, con entrega confiable.*
3. ¿Qué tipos de tópico existen?
   - *Del sistema (servicios de Azure), personalizado, de socio, dominio y de namespace.*
4. ¿Qué es un dominio y cuándo lo usas?
   - *Un tópico con miles de tópicos hijos; SaaS multi-cliente.*
5. ¿Qué garantía de entrega tiene?
   - *Al menos una vez, sin orden.*
6. ¿Qué pasa si el destino falla?
   - *Reintentos con retroceso exponencial hasta agotar intentos/tiempo; luego dead-letter si está configurado, o descarte.*
7. ¿Por qué CloudEvents?
   - *Estándar abierto, portable entre sistemas y obligatorio en namespaces.*
8. ¿Cómo se autentica el publicador?
   - *Con Entra ID y el rol *EventGrid Data Sender*; claves desactivables.*
9. ¿Cómo entrega Event Grid sin secretos?
   - *Con la identidad administrada del tópico y roles en el destino.*
10. ¿Event Grid, Service Bus o Event Hubs?
    - *Reaccionar y enrutar → Event Grid; comandos con garantías → Service Bus; streaming/reproducción → Event Hubs.*
11. ¿Qué es el handshake?
    - *Validación del webhook al crear la suscripción.*
12. ¿Push o pull?
    - *Push: inmediato, el servicio entrega. Pull (namespaces): tú pides y confirmas, controlas el ritmo.*
13. ¿Cómo evitas el bucle de eventos?
    - *No reaccionar a eventos propios; filtros y campo de origen.*

## Entrevista
- Diseña la integración de pedidos, pagos e inventario con eventos y justifica dónde usas Service Bus.
- ¿Cómo garantizas que no se procese dos veces un evento de pago?
- ¿Cómo reaccionas a la expiración de certificados y secretos en toda la organización?
- ¿Cuándo prefieres pull sobre push?

## Ejercicio práctico
1. Despliega el [Terraform](ejemplos/terraform/main.tf).
2. Publica los [eventos de ejemplo](ejemplos/eventos/) con la [CLI](ejemplos/cli/event-grid.sh) y mira cuáles llegan a la cola.
3. Provoca un fallo (quita el rol *Data Sender* del tópico) y observa métricas y dead-letter.
4. Consume y rota un secreto con el código de [uso en Java](uso-en-java.md).
5. Prueba la entrega pull del namespace.
