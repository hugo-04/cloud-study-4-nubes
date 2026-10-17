# Google Cloud · Gobierno · Cloud Audit Logs · Casos reales

## 1. ¿Quién abrió el firewall?
**Qué pasó:** apareció una regla `0.0.0.0/0` al puerto 22 en ModaLima.
**Causa:** un desarrollador probando.
**Arreglo:** filtro `methodName:"firewalls.insert"` en Admin Activity → persona y hora en segundos; alerta para el futuro.
**Lección:** Admin Activity siempre está; úsalo.

## 2. El secreto leído
**Qué pasó:** sospecha de uso indebido de la contraseña de la pasarela de pagos.
**Causa:** Data Access de Secret Manager desactivado: no había rastro.
**Arreglo:** activar `DATA_READ` en Secret Manager para prod.
**Lección:** decide antes qué lecturas importa registrar.

## 3. La factura de logs
**Qué pasó:** Café Andino activó Data Access para todos los servicios y la factura de Logging se multiplicó.
**Causa:** lecturas de Cloud Storage de alto volumen.
**Arreglo:** Data Access solo en servicios sensibles; exención para la cuenta del CDN.
**Lección:** calcula el volumen.

## 4. Los logs borrados
**Qué pasó:** tras un incidente, el atacante borró el bucket de logs del proyecto.
**Causa:** logs en el mismo proyecto con dueños amplios.
**Arreglo:** sink agregado a un proyecto de seguridad con bucket bloqueado.
**Lección:** la evidencia vive fuera del alcance del sospechoso.

## Resumen
| # | Situación | Causa | Arreglo |
|---|---|---|---|
| 1 | Cambio sospechoso | — | Filtro en Admin Activity |
| 2 | Sin rastro | Data Access apagado | Activar donde importa |
| 3 | Costo | Todo activado | Selectivo + exención |
| 4 | Evidencia borrada | Mismo proyecto | Sink + bucket bloqueado |
