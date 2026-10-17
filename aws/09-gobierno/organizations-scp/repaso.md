# AWS · Organizations y SCP · Repaso

## Preguntas
1. ¿Una SCP concede permisos?
   - *No: solo fija el techo; los permisos vienen de IAM.*
2. ¿Qué cuenta no está limitada por las SCP?
   - *La cuenta de administración.*
3. ¿Lista de denegación o de permitidos?
   - *Denegación sobre `FullAWSAccess` (más simple y mantenible).*
4. ¿Cómo se calcula el permiso efectivo?
   - *IAM ∩ SCP de la raíz ∩ SCP de cada OU ∩ SCP de la cuenta.*
5. ¿Por qué la SCP de regiones usa `NotAction`?
   - *Para no bloquear servicios globales (IAM, STS, Route 53…).*
6. ¿Para qué un rol de emergencia?
   - *Para recuperarse de un error; se excluye por condición y se alarma.*
7. ¿Cómo corriges una SCP que bloqueó todo?
   - *Desde la cuenta de administración, desadjuntándola.*
8. ¿Cómo reconoces un rechazo por SCP?
   - *El mensaje dice *explicit deny in a service control policy*.*
9. ¿Qué diferencia hay entre SCP y Config?
   - *La SCP previene; Config detecta e informa incumplimientos.*
10. ¿Por qué la cuenta de administración no debe tener cargas?
    - *Porque no se puede limitar con SCP y es la más sensible.*

## Ejercicios
1. Diseña un árbol de OU para ModaLima y asigna una SCP a cada una.
2. Escribe una SCP de regiones con `NotAction` y pásala por el validador.
3. Crea una SCP que obligue IMDSv2 y pruébala en una cuenta sandbox.
4. Simula el bloqueo total y describe cómo lo corregirías.

## Autoevaluación
- [ ] Explico que la SCP es un techo, no una concesión.
- [ ] Diseño OU por función y riesgo.
- [ ] Excluyo el rol de emergencia por condición.
- [ ] Pruebo cada SCP en una OU de ensayo.
- [ ] Mantengo la cuenta de administración sin cargas.
