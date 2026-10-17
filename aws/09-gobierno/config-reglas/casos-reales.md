# AWS · Config · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. El bucket público que nadie vio
**Qué pasó:** un equipo abrió un bucket para «compartir una carpeta» y quedó público tres semanas. **Solución:** regla administrada de lectura/escritura pública prohibida, con notificación a EventBridge → canal de seguridad y remediación manual aprobada. **Lección:** Config detecta en minutos lo que una revisión mensual encuentra en semanas.

## 2. Recursos sin dueño
**Qué pasó:** la factura traía 40 instancias sin `centro-costo`; nadie sabía de quién eran. **Solución:** regla de etiquetas obligatorias (clave y valores permitidos) y un reporte semanal de incumplimientos por equipo. **Lección:** sin etiquetas no hay dueño; sin dueño no hay costo atribuible.

## 3. «¿Quién cambió el grupo de seguridad?»
**Qué pasó:** un puerto se abrió al mundo y se cerró dos horas después. **Solución:** línea de tiempo del recurso en Config (qué cambió y cuándo) cruzada con CloudTrail (quién). **Lección:** Config dice *qué*, CloudTrail dice *quién*: úsalos juntos.

## 4. La remediación automática que apagó producción
**Qué pasó:** una remediación automática «detener instancias sin etiqueta de entorno» detuvo instancias de producción mal etiquetadas. **Solución:** remediar solo acciones reversibles y no destructivas, con alcance por etiqueta y primero en manual. **Lección:** automatizar la corrección es automatizar el error.

## 5. La factura de Config
**Qué pasó:** el costo de Config creció por grabar continuamente tipos que cambian todo el rato y que nadie evaluaba. **Solución:** registrar solo los tipos útiles, frecuencia diaria donde basta, y revisar el costo por tipo. **Lección:** graba lo que evalúas o necesitas auditar.

## 6. La regla personalizada que dejó evaluaciones colgadas
**Qué pasó:** la Lambda de una regla no manejaba los recursos eliminados ni los elementos grandes; quedaban `INSUFFICIENT_DATA` y el panel mentía. **Solución:** reportar `NOT_APPLICABLE` para eliminados y fuera de alcance, recuperar el elemento completo si es grande, y reintentar `PutEvaluations` fallidas. **Lección:** una regla personalizada debe responder siempre, y por cada recurso.

## Resumen

| # | Problema | Pieza que lo resolvió |
|---|---|---|
| 1 | Bucket público | Regla administrada + EventBridge |
| 2 | Recursos sin dueño | Regla de etiquetas + reporte |
| 3 | Cambio sin autor | Línea de tiempo + CloudTrail |
| 4 | Remediación destructiva | Solo acciones reversibles, manual primero |
| 5 | Costo de Config | Registro selectivo y frecuencia diaria |
| 6 | Evaluaciones colgadas | `NOT_APPLICABLE`, elemento completo, reintento |
