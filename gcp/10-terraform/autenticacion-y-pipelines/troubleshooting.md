# Google Cloud · Terraform · Autenticación y pipelines · Troubleshooting

## Lista ordenada
1. **¿El token OIDC tiene los claims esperados?** Repo, rama, entorno, audiencia.
2. **¿La condición del proveedor los acepta?** Error `unauthorized_client` si no.
3. **¿El principalSet tiene `workloadIdentityUser` sobre la SA?**
4. **¿La SA tiene los roles del entorno?**
5. **¿El archivo `external_account` está en `GOOGLE_APPLICATION_CREDENTIALS`?**

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `unauthorized_client` / condición | Claims no cumplen | Revisa la condición CEL |
| `iam.serviceAccounts.getAccessToken denied` | Falta workloadIdentityUser | Rol al principalSet |
| `403` en recursos | Roles de la SA | Ajusta roles mínimos |
| Plan pide credenciales | ADC no encuentra el archivo | Variable de entorno |
| `Saved plan is stale` | El estado cambió | Vuelve a planificar |
