# Google Cloud · Mensajería · Eventarc · Casos reales

## 1. El cambio de IAM silencioso
**Qué pasó:** alguien dio `roles/owner` a un usuario externo en un proyecto de ModaLima y nadie se enteró.
**Causa:** sin vigilancia de `SetIamPolicy`.
**Arreglo:** disparador de Audit Logs para `SetIamPolicy` → Cloud Run que alerta y revisa miembros externos.
**Lección:** reacciona a los cambios de seguridad en minutos.

## 2. El disparador que no disparaba
**Qué pasó:** el disparador de Audit Logs para lecturas de secretos nunca se activó.
**Causa:** los Data Access logs de Secret Manager estaban desactivados.
**Arreglo:** activar esos registros (con costo controlado).
**Lección:** sin registro no hay evento.

## 3. Alertas duplicadas
**Qué pasó:** el equipo de Café Andino recibía alertas repetidas.
**Causa:** reentregas y el receptor no deduplicaba.
**Arreglo:** dedupe por `ce-id` + `ce-source`.
**Lección:** al menos una vez también aquí.

## 4. Demasiados eventos
**Qué pasó:** el destino recibía miles de eventos por minuto irrelevantes.
**Causa:** filtro solo por tipo de evento de Audit Logs.
**Arreglo:** filtros por `serviceName` y `methodName`.
**Lección:** filtra en el disparador, no en el código.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Cambio sin aviso | Sin disparador | Audit Logs → alerta |
| 2 | Nada dispara | Logs desactivados | Activar Data Access |
| 3 | Duplicados | Reentrega | Dedupe por ce-id |
| 4 | Ruido | Filtro amplio | Servicio + método |
