# Google Cloud · Gobierno · Presupuestos y costos · Repaso

## Preguntas
1. ¿Un presupuesto detiene el gasto?
2. ¿Qué es un umbral pronosticado?
3. ¿Dónde se ve el costo por label?
4. ¿Cómo calculas el costo neto?
5. ¿La exportación es retroactiva?
6. ¿Cómo frenas un proyecto de sandbox?
7. ¿Por qué cuotas y Org Policy son control de costos?
8. ¿Qué es Recommender?
9. ¿Qué riesgo tiene desvincular la facturación?
10. ¿Cada cuánto llega el mensaje del presupuesto?

## Respuestas
1. No: avisa.
2. Un aviso según el gasto proyectado a fin de periodo.
3. En la exportación a BigQuery.
4. `cost` más la suma de `credits`.
5. No.
6. Pub/Sub → función que escala a cero o detiene recursos.
7. Limitan lo que se puede crear y dónde.
8. Sugerencias de ahorro por recurso.
9. Apaga recursos y puede perder datos.
10. Varias veces al día, aunque no cambie el umbral.

## Ejercicios
1. Define presupuestos de ModaLima por entorno.
2. Escribe la consulta de los 5 servicios más caros por equipo.
3. Diseña la reacción idempotente a los mensajes.
