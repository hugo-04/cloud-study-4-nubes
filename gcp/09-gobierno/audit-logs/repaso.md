# Google Cloud · Gobierno · Cloud Audit Logs · Repaso

## Preguntas
1. ¿Cuáles son los cuatro tipos?
2. ¿Cuáles están siempre activos?
3. ¿Dónde se activa Data Access?
4. ¿Qué campos identifican quién y qué?
5. ¿Qué es un sink agregado?
6. ¿Por qué un bucket bloqueado?
7. ¿Qué rol permite ver Data Access?
8. ¿Qué retención tiene `_Required`?
9. ¿Cómo alertas en minutos?
10. ¿Qué cuesta?

## Respuestas
1. Admin Activity, Data Access, System Event y Policy Denied.
2. Admin Activity y System Event.
3. En los `auditConfigs` de la política IAM.
4. `authenticationInfo.principalEmail` y `methodName` (con `serviceName` y `resourceName`).
5. Un sink en organización o carpeta que incluye a los hijos.
6. Para que nadie acorte la retención ni borre evidencia.
7. `roles/logging.privateLogViewer`.
8. 400 días.
9. Con métricas basadas en logs o Eventarc.
10. Data Access y Policy Denied por ingesta y almacenamiento.

## Ejercicios
1. Escribe el filtro para cambios de IAM de la última hora.
2. Decide qué servicios llevan Data Access en ModaLima.
3. Diseña el proyecto de seguridad con sink y retención.
