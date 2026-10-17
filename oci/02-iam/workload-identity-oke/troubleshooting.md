# Oracle OCI · IAM · Workload Identity en OKE · Troubleshooting

## Lista ordenada
1. **¿El clúster es enhanced?** Si no, no hay workload identity.
2. **¿El pod usa el ServiceAccount correcto?** `kubectl get pod <p> -o jsonpath='{.spec.serviceAccountName}'`.
3. **¿La política cita tipo, clúster, namespace y cuenta correctos?** Una letra distinta basta para fallar.
4. **¿Estás usando el proveedor `oke`** y no `instance` ni el archivo de configuración?
5. **¿Hay acceso de red al servicio?** Puerta NAT o puerta de servicios ([Red](../../01-red/README.md)).
6. **¿Cambio reciente?** Espera unos segundos.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| Error al crear el proveedor | Clúster no enhanced o variables de entorno ausentes | Verifica tipo de clúster |
| 404 `NotAuthorizedOrNotFound` | Política no coincide con los atributos | Compara cada atributo |
| Funciona con un pod y no con otro | ServiceAccount distinto | Revisa `serviceAccountName` |
| Timeout al llamar al servicio | Sin ruta de salida | Puerta NAT / de servicios |
| Funciona en dev y no en prod | `cluster_id` de otro clúster | Usa el OCID correcto |
