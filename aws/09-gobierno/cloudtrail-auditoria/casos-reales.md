# AWS · CloudTrail · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. «¿Quién borró la tabla?»
**Qué pasó:** desapareció una tabla de la cuenta de desarrollo un viernes. **Solución:** `LookupEvents` por `DeleteTable` mostró el rol (sesión asumida desde un pipeline), la hora y la IP; el pipeline tenía una etapa de «limpieza» mal configurada. **Lección:** sin registro habría sido una discusión; con registro fue un arreglo de cinco minutos.

## 2. El inicio de sesión sin MFA
**Qué pasó:** un usuario de IAM inició sesión en la consola sin MFA desde un país inesperado. **Solución:** filtro de métrica sobre `ConsoleLogin` exitoso con `MFAUsed != Yes`, alarma a seguridad y política que exige MFA. **Lección:** la detección útil es la que avisa en minutos, no la que se descubre en la auditoría.

## 3. La traza apagada
**Qué pasó:** alguien detuvo la traza «porque costaba». Hubo 12 horas sin registros. **Solución:** SCP que prohíbe `StopLogging`/`DeleteTrail`, alarma ante cualquier intento y traza de organización que los miembros no pueden tocar. **Lección:** quien vigila no debe poder apagar la cámara.

## 4. La ráfaga de `AccessDenied`
**Qué pasó:** un rol de servicio comprometido exploraba la cuenta: cientos de `AccessDenied` en dos minutos sobre servicios que nunca usaba. **Solución:** detector por ventana (≥ 20 rechazos por principal en 5 minutos) que alerta y adjunta los servicios tocados. **Lección:** un rechazo aislado es ruido; una ráfaga es una señal.

## 5. La factura de eventos de datos
**Qué pasó:** se activaron eventos de datos de S3 en todos los buckets; el costo se disparó con millones de lecturas de imágenes del catálogo. **Solución:** limitar los eventos de datos al bucket de documentos sensibles y a escrituras. **Lección:** auditar todo es auditar nada: elige qué importa.

## 6. Investigar tres meses sin descargar nada
**Qué pasó:** una auditoría pidió la actividad de un rol durante 90+ días. **Solución:** tabla de Athena con proyección de particiones sobre el bucket de la traza y una consulta acotada por fecha y rol. **Lección:** el historial de 90 días no alcanza; la traza a S3 más Athena sí.

## Resumen

| # | Problema | Pieza que lo resolvió |
|---|---|---|
| 1 | Recurso borrado sin autor | `LookupEvents` / historial |
| 2 | Inicio de sesión sin MFA | Filtro de métrica + alarma |
| 3 | Traza apagada | SCP + traza de organización |
| 4 | Exploración con rol comprometido | Detector de ráfagas |
| 5 | Costo de eventos de datos | Eventos de datos selectivos |
| 6 | Auditoría de largo plazo | Traza a S3 + Athena |
