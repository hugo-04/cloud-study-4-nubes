# Oracle OCI · Red · Service Gateway, endpoints privados y DNS privado · Troubleshooting

## Lista ordenada
1. **DNS desde el pod:** `nslookup <nombre>`; ¿devuelve IP privada?
2. **Vista y resolutor:** ¿la vista privada está asociada al resolutor de **esta** VCN?
3. **Ruta:** ¿la subred tiene la ruta al CIDR del servicio (SGW) o al endpoint?
4. **Seguridad:** ¿NSG/lista permiten el puerto hacia el endpoint o el CIDR de servicio?
5. **Identidad:** ¿el principal tiene la política del servicio? (un 401/403 no es de red).

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| El nombre no resuelve | Vista no asociada o zona sin el registro | Asocia la vista; revisa el rrset |
| Resuelve a IP pública | FQDN público o vista ausente | Usa el nombre privado |
| *Timeout* a Object Storage | Sin ruta al SGW o salida bloqueada | Ruta `SERVICE_CIDR_BLOCK` + regla de salida |
| `NotAuthorizedOrNotFound` | Política IAM faltante | [IAM](../../02-iam/README.md) |
| Falla solo desde on-premises | Falta endpoint de escucha | Crea el endpoint de escucha del resolutor |
