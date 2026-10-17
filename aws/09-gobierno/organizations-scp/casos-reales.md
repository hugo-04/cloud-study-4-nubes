# AWS · Organizations y SCP · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. La cuenta de pruebas que minó criptomonedas en 12 regiones
**Qué pasó:** credenciales filtradas de una cuenta sandbox lanzaron instancias grandes en regiones que ModaLima nunca usó. Nadie miraba esas regiones. **Solución:** SCP de regiones (`Deny` con `NotAction` de servicios globales y `aws:RequestedRegion` fuera de `us-east-1`/`sa-east-1`) en toda la organización. **Lección:** lo que no puedes usar no te lo pueden cobrar.

## 2. «Apagué CloudTrail para ahorrar»
**Qué pasó:** un administrador de una cuenta de desarrollo detuvo la traza; dos semanas sin auditoría. **Solución:** SCP que niega `StopLogging`, `DeleteTrail`, `UpdateTrail` y la detención de Config, salvo el rol de emergencia, más una alarma si alguien lo intenta. **Lección:** las pruebas de auditoría no pueden depender de la buena voluntad.

## 3. «Soy administrador y no puedo»
**Qué pasó:** un equipo, con `AdministratorAccess`, recibía `AccessDenied` al crear un bucket en otra región. **Diagnóstico:** el mensaje decía *explicit deny in a service control policy*; la barrera, no su política, bloqueaba. **Solución:** documentar las barreras y enseñar a leer ese mensaje; el cambio legítimo se pide por el repositorio de SCP. **Lección:** el techo existe aunque no lo veas desde la cuenta.

## 4. El `Deny *` que dejó a todos fuera
**Qué pasó:** una SCP con `Deny` sobre `*` y una condición mal escrita se adjuntó a Producción y bloqueó incluso los despliegues y el rol de emergencia. **Solución:** se desadjuntó la política desde la cuenta de administración (que las SCP no limitan). **Lección:** probar en una OU de ensayo, validar con un linter, y proteger la cuenta de administración.

## 5. Las cargas en la cuenta de administración
**Qué pasó:** una API vivía en la cuenta de administración «porque era la primera»; las SCP no podían limitarla y había una clave de acceso antigua. **Solución:** migrar las cargas a una cuenta de Producción y dejar la de administración solo para facturación y políticas. **Lección:** la cuenta que no se puede limitar no debe tener nada que limitar.

## 6. Mover una cuenta de OU rompió el despliegue
**Qué pasó:** al mover una cuenta a la OU de Producción, el despliegue falló: la SCP de regiones no excluía CloudFront ni Route 53. **Solución:** `NotAction` con los servicios globales; pruebas en la OU de ensayo antes de mover cuentas. **Lección:** una SCP se prueba con los despliegues reales.

## Resumen

| # | Problema | Pieza que lo resolvió |
|---|---|---|
| 1 | Cuenta comprometida usando regiones ajenas | SCP de regiones con `NotAction` |
| 2 | Auditoría apagada | SCP de protección + alarma |
| 3 | «Admin sin permisos» | Leer el error de SCP; repositorio de políticas |
| 4 | Bloqueo total | Desadjuntar desde la cuenta de administración; OU de ensayo; linter |
| 5 | Cargas sin límite | Migrar fuera de la cuenta de administración |
| 6 | Despliegue roto al mover | Servicios globales en `NotAction`; pruebas previas |
