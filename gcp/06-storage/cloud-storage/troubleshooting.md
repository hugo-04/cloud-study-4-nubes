# Google Cloud · Storage · Cloud Storage · Troubleshooting

## Lista ordenada
1. **¿Nombre del bucket y del objeto?** Los buckets son globales; el objeto distingue mayúsculas.
2. **¿Rol en el bucket?** `objectViewer`/`objectCreator`/`objectUser`.
3. **¿Acceso público bloqueado?** Esperado si lo intentas.
4. **¿412?** Tu precondición hizo su trabajo.
5. **¿CMEK?** El agente necesita la llave habilitada.
6. **¿Retención?** Impide borrar o reemplazar.
7. **¿Clase fría?** Cargos mínimos de almacenamiento y recuperación.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| 403 | Falta rol | Rol en el bucket |
| 404 | Nombre o proyecto | Revisa nombre |
| 412 | Precondición | Esperado |
| 429 | Objeto caliente o ráfagas | Reparte nombres/tasa |
| No se puede borrar | Retención/hold | Revisa retención |
