# Google Cloud · Caso integrado · Landing zone · Troubleshooting

## Lista ordenada
1. **¿Se crearon carpetas y proyectos?** `gcloud resource-manager folders list --folder <id>`.
2. **¿Facturación vinculada?** `gcloud billing projects describe`.
3. **¿Proyecto de servicio adjunto al host?** `gcloud compute shared-vpc associated-projects list`.
4. **¿Subredes y permisos `networkUser`?**
5. **¿Políticas efectivas?** `org-policies describe --effective`.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `projectCreator` denegado | Rol del pipeline | Rol en la carpeta |
| Error de facturación | Falta `billing.user` | Rol en la cuenta |
| La app no ve la subred | Sin `networkUser` | Rol sobre la subred |
| Solape detectado | Rango ocupado | Replanifica |
| Política rechaza recursos | Herencia | Ajusta el recurso, no la política |
