# Oracle OCI · Gobierno · Cloud Guard y Security Zones · Repaso

## Preguntas
1. ¿Diferencia entre Cloud Guard y Security Zones?
2. ¿Qué es un target?
3. ¿Qué tipos de detectores hay?
4. ¿Qué hace un *responder*?
5. ¿Qué es la región de reporte?
6. ¿Qué pasa al crear algo que viola una Security Zone?
7. ¿Cómo priorizas los problemas?
8. ¿Cuándo automatizar una corrección?
9. ¿Qué debe tener un descarte?
10. ¿Cuánto cuestan?

## Respuestas
1. Cloud Guard detecta (y corrige); Security Zones previene.
2. El compartimento vigilado con sus recetas.
3. De configuración, actividad, amenazas e instancias.
4. Notifica o corrige automáticamente.
5. Donde se consolidan los problemas.
6. La API rechaza la operación.
7. Por riesgo y antigüedad con SLA y dueño.
8. Cuando la corrección es segura y obvia (bucket público).
9. Motivo, dueño y fecha de revisión.
10. No tienen cargo propio.

## Ejercicios
1. Define los SLA por riesgo para ModaLima.
2. Elige qué correcciones automatizar y cuáles solo notificar.
3. Diseña la receta de Security Zone de prod.
