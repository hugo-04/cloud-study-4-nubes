# Oracle OCI · Terraform · Estado remoto · Troubleshooting

## Lista ordenada
1. **¿Autenticación del backend?** El backend `oci` usa la misma configuración que el provider; el `s3` usa *Customer Secret Key*.
2. **¿Endpoint S3 correcto?** `https://<namespace>.compat.objectstorage.<región>.oraclecloud.com` y `region` del bucket.
3. **¿Permisos sobre el prefijo?** `manage objects` con la condición de nombre correcta.
4. **¿Bloqueado?** Revisa quién tiene el bloqueo y si su ejecución sigue viva.
5. **¿Drift?** `plan -refresh-only` o detección de drift en Resource Manager.
6. **¿Versión del backend?** Atributos cambian entre versiones de Terraform/OpenTofu.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `NoSuchBucket` / 404 | Endpoint o región | Corrige endpoint/namespace |
| `SignatureDoesNotMatch` | Secret key o región en `s3` | Regenera clave; revisa región |
| `Error acquiring the state lock` | Bloqueo vigente o colgado | Espera o `force-unlock` con id |
| `plan` quiere recrear todo | Clave de estado equivocada | Revisa `key` del backend |
| Cambios inesperados | Drift | `refresh-only` y corrige el origen |
