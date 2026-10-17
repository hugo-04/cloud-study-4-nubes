# Oracle OCI · Gobierno · Audit · Repaso

## Preguntas
1. ¿Qué registra Audit?
2. ¿Qué no registra?
3. ¿Cuál es la retención configurable?
4. ¿Dónde se registran los cambios de IAM?
5. ¿Cómo conservas eventos por años?
6. ¿Qué permiso necesitas para leer?
7. ¿Qué campos responden «quién» y «desde dónde»?
8. ¿Por qué evitar cuentas compartidas?
9. ¿Audit cuesta?
10. ¿Cómo detectarías cambios sospechosos?

## Respuestas
1. Las llamadas a la API de OCI.
2. Lo que pasa dentro de tus apps y bases.
3. De 90 a 365 días *(verifica)*.
4. En la región *home*.
5. Con Service Connector hacia Object Storage con retención.
6. `read audit-events`.
7. `principalName` e `ipAddress` en `data.identity`.
8. Porque no se puede atribuir una acción a una persona.
9. No; la copia sí.
10. Reglas sobre eventos sensibles, horario e IP.

## Ejercicios
1. Escribe la lista de `eventName` sensibles de ModaLima.
2. Diseña la retención de 7 años para Café Andino.
3. Consulta quién modificó listas de seguridad la última semana.
