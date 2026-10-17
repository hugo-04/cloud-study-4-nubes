# Oracle OCI · Gobierno · Cloud Guard y Security Zones · Casos reales

## 1. El bucket público de los viernes
**Qué pasó:** cada tanto aparecía un bucket público en ModaLima creado «para compartir rápido».
**Causa:** solo había detección, sin corrección.
**Arreglo:** *responder* automático que vuelve privado el bucket y notifica al creador; PAR como alternativa documentada.
**Lección:** lo obvio y peligroso se corrige solo.

## 2. 600 problemas sin dueño
**Qué pasó:** Cloud Guard tenía cientos de problemas y nadie los miraba.
**Causa:** sin priorización ni SLA.
**Arreglo:** triaje diario por riesgo y antigüedad, asignado por etiqueta `centro_costo`.
**Lección:** una herramienta de detección sin proceso es ruido.

## 3. La VM con IP pública en prod
**Qué pasó:** un equipo creó una VM con IP pública en producción para depurar.
**Causa:** prod no era Security Zone.
**Arreglo:** Security Zone en prod; acceso por Bastion.
**Lección:** en prod, prevenir es mejor que detectar.

## 4. El descarte eterno
**Qué pasó:** una excepción «temporal» de Café Andino duró dos años.
**Causa:** descartes sin fecha de revisión.
**Arreglo:** cada descarte con motivo, dueño y fecha; reporte mensual de excepciones.
**Lección:** las excepciones también vencen.

## Resumen
| # | Síntoma | Causa | Arreglo |
|---|---|---|---|
| 1 | Bucket público recurrente | Solo detección | Responder automático |
| 2 | Problemas ignorados | Sin triaje | SLA por riesgo |
| 3 | IP pública en prod | Sin prevención | Security Zone |
| 4 | Excepción eterna | Sin vencimiento | Motivo + fecha |
