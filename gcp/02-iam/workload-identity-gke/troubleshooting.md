# Google Cloud · IAM · Workload Identity en GKE · Troubleshooting

## Lista ordenada
1. **¿Clúster con workload pool?** `workloadIdentityConfig.workloadPool`.
2. **¿Node pool con `GKE_METADATA`?**
3. **¿El pod usa la KSA esperada?** `spec.serviceAccountName`.
4. **¿Qué identidad ve el pod?** `curl -H 'Metadata-Flavor: Google' http://metadata.google.internal/computeMetadata/v1/instance/service-accounts/default/email`.
5. **¿Rol al principal correcto?** Número de proyecto (no ID) en `principal://`.
6. **Modo suplantación:** anotación en la KSA + `workloadIdentityUser`.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| 403 con el principal directo | Número de proyecto o ns/ksa errados | Corrige el principal |
| El pod se ve como la cuenta del nodo | Sin `GKE_METADATA` | Node pool correcto |
| `Unable to generate access token` | Falta `workloadIdentityUser` | Otórgalo |
| Funciona en un pod y no en otro | KSA distinta | Revisa el deployment |
| Primeros segundos fallan | Metadata server aún no listo | Reintentos al arrancar |
