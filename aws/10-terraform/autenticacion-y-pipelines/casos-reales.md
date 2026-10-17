# AWS · Autenticación y pipelines · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. La clave en el secreto del repositorio
**Qué pasó:** el pipeline usaba una clave de acceso guardada como secreto; apareció en el registro de una ejecución depurada con `set -x`. **Solución:** se rotó, se migró a OIDC (sin claves) y se eliminó el usuario de IAM. **Lección:** el mejor secreto es el que no existe.

## 2. El `sub` con comodín
**Qué pasó:** la política de confianza del rol de producción aceptaba `repo:modalima/*`. Un repositorio de pruebas, con permisos de escritura para todos, pudo asumir el rol. **Solución:** `sub` exacto `repo:modalima/infra:environment:prod` y validación automática de las políticas de confianza. **Lección:** el comodín en el `sub` es una puerta abierta a toda la organización.

## 3. El PR que podía aplicar
**Qué pasó:** un pull request modificó el flujo de trabajo para ejecutar `apply`, y el rol único lo permitió. **Solución:** rol de `plan` (solo lectura) para PR y rol de `apply` solo para el entorno protegido con aprobación; flujos de trabajo protegidos por revisión de código. **Lección:** separa lo que cualquiera puede ejecutar de lo que exige aprobación.

## 4. El `apply` cancelado
**Qué pasó:** una ejecución se canceló a medias por una nueva confirmación; quedó el candado y un estado parcial. **Solución:** `concurrency` por entorno con `cancel-in-progress: false`, y guía para resolver el candado. **Lección:** nunca canceles un `apply` en curso.

## 5. El plan que borraba la base de datos
**Qué pasó:** un cambio de nombre en el código hacía que el plan **reemplazara** una base de datos. Nadie lo notó en un plan de 400 líneas. **Solución:** la puerta de seguridad detecta destrucción de recursos con datos y bloquea hasta una excepción documentada. **Lección:** las personas fallan leyendo planes largos; las máquinas no se cansan.

## 6. El puerto abierto a mano
**Qué pasó:** alguien abrió el puerto 22 al mundo desde la consola «solo un rato». **Solución:** el plan nocturno detectó la deriva, avisó al canal de operaciones y el siguiente `apply` lo corrigió. **Lección:** lo que no se vigila, se desvía.

## Resumen

| # | Problema | Pieza que lo resolvió |
|---|---|---|
| 1 | Clave filtrada | OIDC (sin secretos) |
| 2 | Cualquier repo asumía producción | `sub` exacto + validador |
| 3 | PR con poder de `apply` | Roles separados + entorno protegido |
| 4 | Estado parcial por cancelación | `concurrency` sin cancelar |
| 5 | Reemplazo silencioso de la base de datos | Puerta sobre `plan.json` |
| 6 | Cambio manual en la red | Deriva nocturna |
