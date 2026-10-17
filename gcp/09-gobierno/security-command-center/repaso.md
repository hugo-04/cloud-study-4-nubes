# Google Cloud · Gobierno · Security Command Center · Repaso

## Preguntas
1. ¿Qué detecta Security Health Analytics?
2. ¿Y Event Threat Detection?
3. ¿Qué campos tiene un hallazgo?
4. ¿Qué es el mute?
5. ¿Cómo notificas hallazgos?
6. ¿Qué rol permite cambiar el estado?
7. ¿Qué hacer con un hallazgo repetido?
8. ¿Por qué no notificar todo?
9. ¿Qué agregan los niveles superiores?
10. ¿Dónde investigas quién causó el hallazgo?

## Respuestas
1. Configuraciones inseguras.
2. Amenazas a partir de logs.
3. Categoría, severidad, estado, clase, recurso y hora del evento.
4. Silenciar hallazgos aceptados con reglas.
5. Con una configuración de notificación hacia Pub/Sub.
6. `roles/securitycenter.findingsEditor`.
7. Prevenirlo con una política de organización.
8. Por fatiga de alertas.
9. Más detectores, rutas de ataque y cumplimiento.
10. En Audit Logs.

## Ejercicios
1. Define SLA por severidad para ModaLima.
2. Escribe el filtro de notificación para críticos activos.
3. Diseña la revisión trimestral de mutes.
