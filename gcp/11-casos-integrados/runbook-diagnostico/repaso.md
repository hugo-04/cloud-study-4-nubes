# Google Cloud · Caso integrado · Runbook de diagnóstico · Repaso

## Preguntas
1. ¿En qué orden se revisan las capas?
2. ¿Qué indica un 502 del LB?
3. ¿Qué métrica da la tasa de 5xx?
4. ¿Qué se hace primero: mitigar o causa raíz?
5. ¿Cómo se revierte en Cloud Run?
6. ¿Qué es un resultado desconocido?
7. ¿Dónde ves los cambios recientes?
8. ¿Qué permisos tiene la guardia?
9. ¿Qué retraso tienen las métricas?
10. ¿Qué cierra un incidente?

## Respuestas
1. Borde, backends, cómputo, dependencias, cambios.
2. Que el LB no obtuvo respuesta válida de un backend (a menudo sin backends sanos).
3. `request_count` del LB por `response_code_class`.
4. Mitigar.
5. Enviando el tráfico a la revisión anterior.
6. Un chequeo que no pudo ejecutarse; cuenta como hallazgo.
7. En Audit Logs y en el historial de revisiones y del pipeline.
8. Ver métricas y logs y revertir, no crear infraestructura.
9. De 1 a 3 minutos.
10. El postmortem con acciones.

## Ejercicios
1. Escribe el runbook de 504.
2. Agrega la capa de Pub/Sub al triage.
3. Diseña la alerta de 5xx con umbral y duración.
