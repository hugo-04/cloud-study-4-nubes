# Google Cloud · IAM · Cuentas de servicio · Troubleshooting

## Lista ordenada
1. **¿Qué cuenta usa el recurso?** Revisa la configuración del servicio (Cloud Run, VM, KSA).
2. **¿El que despliega tiene `serviceAccountUser` sobre esa cuenta?**
3. **¿Suplantación?** El llamador necesita `serviceAccountTokenCreator` y la API IAM Credentials habilitada.
4. **¿La cuenta está deshabilitada?**
5. **¿Roles en el recurso correcto?** Proyecto vs recurso.
6. **¿Alcances (scopes) de la VM?** En VMs antiguas, los scopes limitan además de IAM.

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `iam.serviceAccounts.actAs` denegado | Falta `serviceAccountUser` | Otórgalo sobre la cuenta |
| `getAccessToken` denegado | Falta `TokenCreator` | Otórgalo con condición |
| 403 en la app | Rol de datos faltante | Rol mínimo |
| `invalid_grant` | Cuenta deshabilitada/borrada | Revisa el estado |
| Token sin permisos esperados | Scopes de VM | `cloud-platform` + IAM |
