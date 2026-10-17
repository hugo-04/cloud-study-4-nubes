# Google Cloud · Gobierno · Jerarquía y etiquetas · Troubleshooting

## Lista ordenada
1. **¿Dónde está el recurso?** `gcloud projects get-ancestors`.
2. **¿Qué hereda?** Política de IAM efectiva (Policy Analyzer) y tags efectivos.
3. **¿Tag o label?** Las condiciones solo ven tags.
4. **¿Permiso para vincular?** `tagUser` sobre el valor y permiso sobre el recurso.
5. **¿Formato?** Labels en minúsculas, ≤ 63 caracteres.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| La condición `matchTag` no aplica | Tag no vinculado o ID equivocado | Revisa tags efectivos y el ID corto |
| `PERMISSION_DENIED` al vincular | Falta `tagUser` | Rol sobre el valor |
| Label rechazado | Mayúsculas o caracteres | Normaliza |
| Acceso inesperado | Herencia | Policy Analyzer |
| No se puede borrar el proyecto | Lien | Quita el lien con permiso |
