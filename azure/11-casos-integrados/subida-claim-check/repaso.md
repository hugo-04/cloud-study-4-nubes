# Azure · Caso integrado · Subida con Claim Check · Repaso

## Preguntas
1. ¿Por qué la subida va directo a Blob y no por la API?
   - *Los bytes por la API son lentos y caros; la API solo autoriza y registra.*
2. ¿Qué lleva una buena SAS para esto?
   - *Delegación de usuario, un solo blob, solo crear/escribir, 10 minutos.*
3. ¿Por qué registrar la fila antes de firmar?
   - *Para que nunca exista una subida que el sistema no conozca.*
4. ¿Para qué sirve la cuarentena?
   - *Es la zona de lo no confiable; nada se usa hasta validarlo y moverlo.*
5. ¿Cómo se sabe el tipo real de un archivo?
   - *Por sus primeros bytes («mágicos»), no por la extensión ni por lo que declara el cliente.*
6. ¿Qué es el Claim Check aquí?
   - *El mensaje lleva la ruta, el tamaño y el hash; el archivo se queda en Blob.*
7. ¿Qué pasa si Event Grid entrega dos veces el evento?
   - *La segunda transición no se cumple porque el estado ya cambió; no se repite el aviso.*
8. ¿Qué hace el conciliador?
   - *Expira pendientes viejas y revalida las `SUBIDA` atascadas.*
9. ¿Por qué `shared_access_key_enabled = false`?
   - *Quita la clave de la cuenta del juego: solo Entra ID y SAS de delegación.*
10. ¿Por qué el nombre del blob lo genera el servidor?
    - *Evita colisiones, sobrescrituras y rutas manipuladas.*
11. ¿Qué rol necesita la API para firmar una SAS de delegación?
    - *Storage Blob Delegator en la cuenta, más permisos de datos que la SAS heredará.*
12. ¿Qué falla si no configuras CORS?
    - *El navegador bloquea la subida directa; `curl` no lo muestra.*

## Ejercicios
1. Dibuja la máquina de estados y marca quién ejecuta cada transición.
2. Añade el estado `EN_ESCANEO` entre `SUBIDA` y `VALIDADA`: ¿qué tablas y reglas cambian?
3. Escribe la regla de ciclo de vida para borrar `validados` de más de 5 años.
4. Calcula cuánto espacio extra ocupa la cuarentena con 10 000 subidas/día de 5 MB.
5. Simula un corte entre la copia y la transición a `VALIDADA`: ¿qué pasa en el reintento?

## Autoevaluación
- [ ] Explico por qué los bytes no pasan por la API.
- [ ] Sé por qué una SAS de delegación es mejor que una de clave de cuenta.
- [ ] Puedo describir cada estado y su transición.
- [ ] Sé qué mirar cuando una fila queda en `PENDIENTE`.
