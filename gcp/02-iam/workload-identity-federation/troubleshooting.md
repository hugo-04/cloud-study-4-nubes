# Google Cloud · IAM · Workload Identity Federation · Troubleshooting

## Lista ordenada
1. **¿Token externo válido?** Decodifica el JWT: `iss`, `aud`, `sub`, `exp`.
2. **¿Emisor y audiencia del proveedor coinciden?**
3. **¿La condición es verdadera para ese token?** Prueba con los valores reales.
4. **¿Rol al principal/principalSet correcto?** Número de proyecto y nombre del pool.
5. **Modo suplantación:** `workloadIdentityUser` sobre la cuenta.
6. **¿API STS e IAM Credentials habilitadas?**

| Síntoma | Causa probable | Qué hacer |
|---|---|---|
| `invalid_grant: audience` | Audiencia distinta | Corrige la audiencia |
| `The given credential is rejected by the attribute condition` | Condición falsa | Revisa claims y condición |
| 403 tras intercambio | Falta rol al principalSet | Otorga el rol |
| `Permission iam.serviceAccounts.getAccessToken denied` | Falta `workloadIdentityUser` | Otórgalo |
| Token expirado | Pasos lentos | Pide el token justo antes |
