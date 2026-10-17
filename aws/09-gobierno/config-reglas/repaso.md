# AWS · Config · Repaso

## Preguntas
1. ¿Qué registra Config?
   - *La configuración de los recursos a lo largo del tiempo (elementos de configuración).*
2. ¿Config previene o detecta?
   - *Detecta (y puede remediar); prevenir es trabajo de las SCP.*
3. ¿Qué tipos de regla existen?
   - *Administradas, personalizadas con Lambda y de política (Guard).*
4. ¿Qué disparos tiene una regla?
   - *Cambio de configuración, periódico, o ambos.*
5. ¿Qué resultados existen?
   - *`COMPLIANT`, `NON_COMPLIANT`, `NOT_APPLICABLE`, `INSUFFICIENT_DATA`.*
6. ¿Qué hace una regla personalizada con un recurso eliminado?
   - *Reporta `NOT_APPLICABLE`.*
7. ¿Cuántas evaluaciones cabe en una llamada a `PutEvaluations`?
   - *Hasta 100; partir en lotes y reintentar las fallidas.*
8. ¿Cuándo remediar automáticamente?
   - *Solo acciones seguras y reversibles.*
9. ¿Config o CloudTrail para saber quién cambió algo?
   - *CloudTrail (quién y cuándo); Config muestra qué cambió.*
10. ¿Para qué un agregador?
    - *Ver el cumplimiento de varias cuentas y regiones en un solo lugar.*

## Ejercicios
1. Activa el registrador y una regla de etiquetas obligatorias; revisa el resultado.
2. Escribe una consulta avanzada que liste los volúmenes sin cifrar.
3. Implementa una regla personalizada que valide valores de etiqueta y pruébala con eventos de ejemplo.
4. Diseña una remediación manual para bloquear el acceso público de un bucket.

## Autoevaluación
- [ ] Distingo detectar (Config) de prevenir (SCP) y de auditar (CloudTrail).
- [ ] Empiezo con reglas administradas.
- [ ] Mi regla personalizada responde siempre y por cada recurso.
- [ ] Remedio solo lo seguro y reversible.
- [ ] Controlo el costo de grabación.
