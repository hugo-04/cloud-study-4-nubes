# Google Cloud · Datos · Firestore · Repaso

## Preguntas
1. ¿Qué modelo de datos usa?
2. ¿Qué es una subcolección?
3. ¿Qué índices se crean solos?
4. ¿Cuántas escrituras sostiene un documento?
5. ¿Qué es un contador distribuido?
6. ¿El backend evalúa reglas de seguridad?
7. ¿Qué rol necesita el backend?
8. ¿Para qué sirve el TTL?
9. ¿Cómo se cobra?
10. ¿Cuándo no usar Firestore?

## Respuestas
1. Documentos en colecciones.
2. Una colección dentro de un documento.
3. Los de campo simple.
4. Alrededor de una por segundo sostenida *(verifica)*.
5. Un contador repartido en fragmentos que se suman al leer.
6. No: el SDK de servidor usa IAM.
7. `roles/datastore.user`.
8. Borrar documentos caducados sin jobs.
9. Por operaciones de documento y almacenamiento.
10. Para analítica con joins o telemetría masiva.

## Ejercicios
1. Diseña la estructura de clientes y carritos.
2. Calcula fragmentos para 200 escrituras/s.
3. Escribe el índice compuesto para nivel + fecha.
