# Google Cloud · Caso integrado · Runbook de diagnóstico · Casos reales

## 1. El 502 del Cyber
**Qué pasó:** 502 en toda la tienda de ModaLima a las 21:07.
**Causa:** nueva revisión de Cloud Run con un *readiness* que fallaba; el LB no tenía backends sanos.
**Arreglo:** tráfico al 100 % a la revisión anterior en 1 minuto; corrección del *probe* después.
**Lección:** revertir primero.

## 2. La base inocente
**Qué pasó:** el equipo pasó 30 minutos mirando Cloud SQL.
**Causa:** el problema estaba en el borde: una regla de Cloud Armor bloqueaba a un país.
**Arreglo:** triage por capas desde afuera.
**Lección:** el orden ahorra tiempo.

## 3. El chequeo que no corrió
**Qué pasó:** el triage dijo «todo OK» y la tienda seguía caída.
**Causa:** la cuenta del triage no tenía permisos en Monitoring; los errores se tomaban como OK.
**Arreglo:** «desconocido» como hallazgo.
**Lección:** no comprobar no es comprobar.

## 4. El cambio de red del viernes
**Qué pasó:** Café Andino perdió conexión con la base el viernes a las 18:00.
**Causa:** un apply cambió una regla de firewall.
**Arreglo:** Audit Logs mostró el cambio; se revirtió el commit.
**Lección:** la capa «cambios» siempre se revisa.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | 502 | Revisión mala | Revertir tráfico |
| 2 | Tiempo perdido | Orden incorrecto | Por capas |
| 3 | Falso OK | Sin permisos | Desconocido = hallazgo |
| 4 | Sin conexión | Cambio de firewall | Audit Logs + revertir |
