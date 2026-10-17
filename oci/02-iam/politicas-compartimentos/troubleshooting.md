# Oracle OCI · IAM · Compartimentos, grupos y políticas · Troubleshooting

## Lista ordenada
1. **¿Qué error es?** `NotAuthorizedOrNotFound` (404) = permisos o recurso inexistente; 401 = credenciales.
2. **¿Quién es el principal?** Usuario, grupo dinámico o workload (¿pertenece al grupo correcto?).
3. **¿Existe una frase que lo permita?** Verbo, familia de recursos, compartimento.
4. **¿La política está en el compartimento correcto** (el recurso o un ancestro)?
5. **¿Las condiciones `where` se cumplen?** Nombre del bucket, etiquetas, tipo de principal.
6. **¿Región o dominio de identidad?** Los grupos de un dominio llevan el prefijo del dominio.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| 404 `NotAuthorizedOrNotFound` | Falta frase o compartimento mal | Añade el verbo mínimo |
| Funciona para un usuario y no para otro | Grupos distintos | Revisa pertenencia |
| La frase parece correcta y falla | Nombre del grupo sin dominio | Usa `'Dominio'/'Grupo'` |
| Funciona en dev y no en prod | Política solo en dev | Replica con permisos mínimos |
| Cambios que no surten efecto | Propagación de unos segundos | Espera y reintenta |
