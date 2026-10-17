# AWS · Budgets y Cost Explorer · Casos reales

Historias de ModaLima y Café Andino (ficticias).

## 1. El NAT silencioso
**Qué pasó:** la factura del entorno de desarrollo subió 40 % sin que nadie desplegara nada nuevo. **Solución:** Cost Explorer agrupado por *tipo de uso* mostró el procesamiento de datos del NAT Gateway: un servicio descargaba imágenes de un repositorio externo en bucle. Se añadieron puntos de acceso privados a los servicios de AWS y se corrigió el bucle. **Lección:** agrupa primero por servicio, después por tipo de uso; el culpable suele ser una línea pequeña repetida millones de veces.

## 2. La etiqueta que nunca se activó
**Qué pasó:** el reparto por equipo mostraba 70 % «sin etiqueta», aunque todos los recursos tenían la etiqueta `equipo`. **Solución:** faltaba **activarla en Facturación**; además, había valores `Pagos` y `pagos`. Se activó, se normalizó con una política de etiquetas y el reparto agrupa sin distinguir mayúsculas. **Lección:** etiquetar no basta; activar y normalizar. El porcentaje «sin etiqueta» es un indicador de higiene.

## 3. El presupuesto que avisó tarde
**Qué pasó:** el único aviso estaba al 100 % real; llegó el día 27. **Solución:** avisos **pronosticados** al 80 % y 100 %: el día 12 ya se supo que el mes se pasaría. **Lección:** el pronóstico convierte un susto en una decisión a tiempo.

## 4. El bucle de reintentos
**Qué pasó:** una función con reintentos infinitos sobre un mensaje venenoso consumió cómputo durante cuatro días. **Solución:** una suscripción **inmediata** de Cost Anomaly Detection al chat de operaciones; además, DLQ con límite de reintentos. **Lección:** la anomalía de costos es un síntoma; la causa se corrige en la aplicación, pero el aviso evita cuatro días de factura.

## 5. El tablero que costaba dinero
**Qué pasó:** un panel interno llamaba a la API de Cost Explorer en cada refresco de página; con decenas de personas, la API generó un cargo notable. **Solución:** caché de 30 minutos en el servicio y consulta por mes completo, no por widget. **Lección:** la API de costos cuesta por solicitud; cachea y agrupa.

## 6. El sandbox con tope
**Qué pasó:** un laboratorio dejó clústeres encendidos un fin de semana. **Solución:** presupuesto del sandbox con una **acción** que aplica una política de bloqueo de creación de recursos al 100 % (aprobación manual al inicio) y aviso al equipo; los clústeres se apagan con un horario. **Lección:** el aviso informa; la acción frena. Y el freno no es instantáneo, así que el tope se fija por debajo de lo que dolería.

## Resumen

| # | Problema | Pieza que lo resolvió |
|---|---|---|
| 1 | Aumento sin causa visible | Cost Explorer por tipo de uso |
| 2 | Reparto con 70 % sin etiqueta | Activar etiquetas + normalizar |
| 3 | Aviso demasiado tarde | Aviso pronosticado |
| 4 | Gasto por bucle de reintentos | Anomaly Detection inmediata |
| 5 | Costo de la propia API de costos | Caché y consultas agrupadas |
| 6 | Laboratorio olvidado | Acción de presupuesto + horario |
