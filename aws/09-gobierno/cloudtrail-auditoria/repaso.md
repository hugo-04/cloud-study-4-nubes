# AWS · CloudTrail · Repaso

## Preguntas
1. ¿Qué registra CloudTrail?
   - *Las llamadas a la API: quién, qué, cuándo, desde dónde y con qué resultado.*
2. ¿Qué diferencia hay entre eventos de administración y de datos?
   - *Plano de control frente a plano de datos; los de datos son voluminosos y se activan selectivamente.*
3. ¿Qué cubre el historial de eventos?
   - *Los últimos 90 días de eventos de administración, por región.*
4. ¿Para qué una traza?
   - *Entrega continua a S3 (y CloudWatch Logs) para retención, detección y forense.*
5. ¿Cómo compruebas que los registros no fueron alterados?
   - *Validación de integridad con archivos de resumen firmados.*
6. ¿Cómo detectas el uso del usuario raíz?
   - *Filtro sobre `userIdentity.type = Root` sin `invokedBy` y evento que no sea de servicio.*
7. ¿Por qué usar ventana y umbral en los `AccessDenied`?
   - *Un rechazo aislado es ruido; una ráfaga por principal es una señal.*
8. ¿Qué es una traza de organización?
   - *Una traza que cubre todas las cuentas y que los miembros no pueden apagar.*
9. ¿CloudTrail previene acciones?
   - *No: registra; prevenir es trabajo de las SCP.*
10. ¿Cómo investigas más de 90 días?
    - *Con la traza en S3 + Athena, o CloudTrail Lake.*

## Ejercicios
1. Crea una traza multirregión con validación y alarmas para raíz y falta de MFA.
2. Busca con `LookupEvents` quién ejecutó `DeleteTable` en las últimas 24 horas.
3. Crea la tabla de Athena y consulta los `AccessDenied` por rol de un día.
4. Implementa un detector de ráfagas con ventana y pruébalo con eventos de ejemplo.

## Autoevaluación
- [ ] Distingo administración, datos e Insights.
- [ ] Mi traza es multirregión, cifrada, validada y en una cuenta aparte.
- [ ] Tengo alarmas para lo crítico.
- [ ] Sé investigar con LookupEvents, Athena y Lake.
- [ ] Protejo la traza con SCP.
