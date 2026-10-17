# Google Cloud · Gobierno · Organization Policy · Troubleshooting

## Lista ordenada
1. **¿El error dice «violates constraint»?** El mensaje nombra la restricción.
2. **¿Política efectiva?** `gcloud org-policies describe <constraint> --effective --project <p>`.
3. **¿Herencia?** ¿`inheritFromParent` o `reset` en algún nivel?
4. **¿Condición con tag?** ¿El recurso tiene el tag efectivo esperado?
5. **¿Dry run?** Las violaciones simuladas están en Logging.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `FAILED_PRECONDITION ... constraints/...` | Política aplicada | Ajusta el recurso o pide excepción |
| La política no aplica | Reset abajo | Revisa la efectiva |
| Lista con valores raros | Fusión de herencia | Revisa `inheritFromParent` |
| La excepción no funciona | Tag no efectivo | Vincula el tag |
| Personalizada ignorada | Servicio no compatible | Revisa la lista de recursos compatibles |
