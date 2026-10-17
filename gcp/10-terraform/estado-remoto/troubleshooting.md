# Google Cloud · Terraform · Estado remoto · Troubleshooting

## Lista ordenada
1. **Credenciales:** ¿qué identidad usa ADC en el runner? `gcloud auth list` / variables de federación.
2. **Permisos:** `storage.objects.create/get/delete` en el bucket (objectUser).
3. **Bucket y prefijo:** ¿coinciden con el `backend.tf`?
4. **Candado:** ¿hay `.tflock`? ¿de quién y desde cuándo?
5. **CMEK:** ¿la cuenta de servicio de Cloud Storage puede usar la clave?

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `Error acquiring the state lock` | Candado vigente o huérfano | Espera o `force-unlock` tras confirmar |
| `403 storage.objects.get` | Permisos | Rol en el bucket |
| `bucket doesn't exist` | Bootstrap pendiente | Crea el bucket primero |
| Error de KMS | Clave o permiso | `cryptoKeyEncrypterDecrypter` al agente de Storage |
| Plan quiere recrear todo | Prefijo equivocado | Revisa el backend |
