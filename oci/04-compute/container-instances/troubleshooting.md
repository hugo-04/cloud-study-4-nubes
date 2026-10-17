# Oracle OCI · Compute · Container Instances · Troubleshooting

## Lista ordenada
1. **¿Estado?** `CREATING` largo suele ser descarga de imagen o falta de capacidad; `FAILED` trae `lifecycleDetails`.
2. **¿La imagen se descarga?** Ruta OCIR correcta (`<región>.ocir.io/<namespace>/<repo>:<etiqueta>`), política `read repos` o *pull secret*, y ruta de salida (puerta de servicios hacia OCIR).
3. **¿El contenedor arranca?** Revisa los registros del contenedor (`oci container-instances container retrieve-logs`).
4. **¿Código de salida?** `137` = sin memoria (OOM) o `SIGKILL` tras el apagado ordenado; `1` = error de la app.
5. **¿Red?** Subred, NSG y rutas (NAT o puerta de servicios).
6. **¿Identidad?** Grupo dinámico `resource.type = 'computecontainerinstance'` y política.
7. **¿Cuota?** `LimitExceeded` al crear: revisa límites del servicio y de la forma.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Se queda en `CREATING` | Imagen inaccesible o sin salida a OCIR | Política, ruta, *pull secret* |
| `FAILED` al crear | Sin capacidad en el AD/forma | Otro AD u otra forma flexible |
| Reinicios en bucle | Política `ALWAYS` + app que falla | Registros; cambia a `ON_FAILURE`/`NEVER` |
| Salida 137 | Límite de memoria | Sube memoria del contenedor o de la forma |
| 404 desde el SDK dentro | Falta política del grupo dinámico | Política mínima |
| Dos instancias iguales | Reintento sin `opcRetryToken` | Token determinista |
