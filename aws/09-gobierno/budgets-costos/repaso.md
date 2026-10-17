# AWS · Budgets y Cost Explorer · Repaso

## Preguntas
1. ¿Detiene Budgets el gasto por sí solo?
   - *No. Informa; con acciones puede aplicar un freno que tú definiste, y con retraso.*
2. ¿Por qué un aviso pronosticado además del real?
   - *Porque te enteras a mitad de mes de que te pasarás, no al final.*
3. ¿Qué hace falta para ver costos por una etiqueta?
   - *Etiquetar los recursos y activar la etiqueta en Facturación.*
4. ¿Qué significa «sin etiqueta» en un reparto?
   - *Costos sin la etiqueta: sirve como indicador de higiene.*
5. ¿Qué diferencia hay entre Cost Explorer y Data Exports?
   - *Explorer es consulta rápida (UI/API); Data Exports entrega las líneas detalladas a S3 para Athena.*
6. ¿Cuándo usar Cost Anomaly Detection?
   - *Para detectar picos inesperados sin definir umbrales fijos; inmediata por SNS, resumen por correo.*
7. ¿Por qué cachear las llamadas a `GetCostAndUsage`?
   - *Cada solicitud tiene costo y el dato cambia pocas veces al día.*
8. ¿Qué limita una proyección lineal del gasto?
   - *Pagos por adelantado, picos puntuales y días sin datos; sirve como orientación, no como contrato.*
9. ¿Qué endpoint usan Budgets y Cost Explorer?
   - *Globales: se llaman en `us-east-1`.*
10. ¿Qué precauciones tiene una acción de presupuesto?
    - *Rol de ejecución estrecho, aprobación manual al inicio y un tope por debajo de lo que dolería.*

## Ejercicios
1. Crea un presupuesto mensual por equipo con avisos pronosticado 80 %, pronosticado 100 % y real 100 % hacia un tópico SNS.
2. Activa la etiqueta `equipo` y obtén con la CLI el costo del mes agrupado por esa etiqueta.
3. Implementa en Java la proyección de fin de mes y la detección de picos diarios; pruébalas con datos de ejemplo.
4. Crea un monitor de anomalías por servicio con suscripción inmediata a SNS.

## Autoevaluación
- [ ] Distingo Budgets, Cost Explorer, Anomaly Detection y Data Exports.
- [ ] Mis etiquetas están activadas y normalizadas.
- [ ] Tengo avisos pronosticados y reales, por correo y SNS.
- [ ] Cacheo la API de costos.
- [ ] Sé cuándo una acción de presupuesto ayuda y cuándo es un riesgo.
