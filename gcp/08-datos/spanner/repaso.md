# Google Cloud · Datos · Spanner · Repaso

## Preguntas
1. ¿Qué garantiza Spanner?
2. ¿Qué es TrueTime?
3. ¿Qué es un hotspot?
4. ¿Qué PK conviene?
5. ¿Qué es el interleaving?
6. ¿Cuándo usar lecturas obsoletas?
7. ¿Qué rol necesita la app?
8. ¿Cómo se mide la capacidad?
9. ¿Qué evitar dentro de una transacción?
10. ¿Cuándo preferir Cloud SQL?

## Respuestas
1. Consistencia externa con escala horizontal y SQL.
2. Un reloj con incertidumbre acotada para ordenar transacciones.
3. Escrituras concentradas en una división.
4. UUIDv4 o con prefijo de hash, no crecientes.
5. Guardar las filas hijas junto a su padre.
6. En catálogos y consultas que toleran segundos de retraso.
7. `roles/spanner.databaseUser`.
8. En nodos o unidades de procesamiento.
9. Llamadas externas y trabajo largo.
10. Cuando la escala cabe en una instancia y el costo importa.

## Ejercicios
1. Rediseña una PK `(Fecha, Id)` sin hotspot.
2. Escribe la reserva de stock con reintentos.
3. Calcula PU para pruebas y producción.
